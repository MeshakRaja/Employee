from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

import cv2
import numpy as np

from .config import FaceModuleConfig

ImageInput = str | bytes | bytearray | Path | np.ndarray


@dataclass(slots=True)
class FacePoint:
    x: float
    y: float


@dataclass(slots=True)
class FaceLandmarks:
    eye_a: FacePoint
    eye_b: FacePoint
    nose: FacePoint
    mouth_a: FacePoint
    mouth_b: FacePoint


@dataclass(slots=True)
class PoseEstimate:
    label: str
    yaw: float
    pitch: float
    roll: float


@dataclass(slots=True)
class FaceBox:
    x: int
    y: int
    w: int
    h: int


@dataclass(slots=True)
class DetectedFace:
    box: FaceBox
    score: float
    landmarks: FaceLandmarks | None = None
    raw_detection: np.ndarray | None = None


@dataclass(slots=True)
class ValidationResult:
    ok: bool
    reason: str
    face_count: int
    face: DetectedFace | None = None
    quality_score: float = 0.0


@dataclass(slots=True)
class EmbeddingResult:
    embedding: np.ndarray
    quality_score: float
    face_box: FaceBox
    detector_backend: str


class OpenCVFaceEngine:
    def __init__(self, config: FaceModuleConfig) -> None:
        self.config = config
        self.detector_backend = "opencv_haar_hog"
        self._face_detector: Any | None = None
        self._face_recognizer: Any | None = None
        self._cascade_classifier: Any | None = None
        self._hog = cv2.HOGDescriptor(
            (config.hog_face_size, config.hog_face_size),
            (32, 32),
            (16, 16),
            (16, 16),
            9,
        )
        self._initialise_backends()

    def extract_embedding(self, image_input: ImageInput) -> EmbeddingResult:
        image = self.load_image(image_input)
        validation = self.validate_image(image)
        if not validation.ok or validation.face is None:
            raise ValueError(validation.reason)

        if self.detector_backend == "opencv_sface":
            raw_detection = validation.face.raw_detection
            if raw_detection is None:
                raise ValueError("Unable to align face for embedding extraction.")
            aligned = self._face_recognizer.alignCrop(image, raw_detection.astype(np.float32))
            embedding = self._face_recognizer.feature(aligned).flatten().astype(np.float32)
        else:
            normalized_face = self._prepare_face_for_hog(image, validation.face.box)
            embedding = self._hog.compute(normalized_face).flatten().astype(np.float32)

        return EmbeddingResult(
            embedding=self._normalize_vector(embedding),
            quality_score=validation.quality_score,
            face_box=validation.face.box,
            detector_backend=self.detector_backend,
        )

    def validate_image(self, image_input: ImageInput) -> ValidationResult:
        image = self.load_image(image_input)
        faces = self.detect_faces(image)
        if not faces:
            return ValidationResult(False, "No face detected in the image.", 0)
        if len(faces) > 1:
            return ValidationResult(False, "More than one face detected. Use an image with exactly one face.", len(faces))

        detected_face = faces[0]
        if min(detected_face.box.w, detected_face.box.h) < self.config.min_face_size:
            return ValidationResult(False, "Face is too small for reliable recognition.", 1, detected_face)

        face_crop = self._crop_face(image, detected_face.box, padding_ratio=0.18)
        gray_face = cv2.cvtColor(face_crop, cv2.COLOR_BGR2GRAY)

        blur_score = float(cv2.Laplacian(gray_face, cv2.CV_64F).var())
        brightness = float(gray_face.mean())
        if blur_score < self.config.blur_threshold:
            return ValidationResult(False, "Face image is too blurry.", 1, detected_face)
        if brightness < self.config.min_brightness:
            return ValidationResult(False, "Face image is too dark.", 1, detected_face)
        if brightness > self.config.max_brightness:
            return ValidationResult(False, "Face image is too bright.", 1, detected_face)

        quality_score = self._quality_score(
            blur_score=blur_score,
            brightness=brightness,
            face_box=detected_face.box,
            image_shape=image.shape,
        )
        return ValidationResult(True, "valid", 1, detected_face, quality_score)

    def detect_faces(self, image: np.ndarray) -> list[DetectedFace]:
        if self.detector_backend == "opencv_sface":
            height, width = image.shape[:2]
            
            # Recreate with 0.15 limit so it bypasses all washout filters
            self._face_detector = cv2.FaceDetectorYN.create(
                str(self.config.yunet_model_path),
                "",
                (320, 320),
                0.15,
                0.3,
                5000,
            )
            self._face_detector.setInputSize((width, height))
            _, raw_faces = self._face_detector.detect(image)
            if raw_faces is None:
                return []

            detections: list[DetectedFace] = []
            for raw_face in raw_faces:
                x, y, w, h = raw_face[:4]
                detections.append(
                    DetectedFace(
                        box=FaceBox(
                            x=max(int(x), 0),
                            y=max(int(y), 0),
                            w=max(int(w), 0),
                            h=max(int(h), 0),
                        ),
                        score=float(raw_face[-1]),
                        landmarks=self._extract_landmarks(raw_face),
                        raw_detection=raw_face,
                    )
                )
            return sorted(detections, key=lambda item: item.score, reverse=True)

        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        raw_faces = self._cascade_classifier.detectMultiScale(
            gray,
            scaleFactor=1.1,
            minNeighbors=3,
            minSize=(self.config.min_face_size, self.config.min_face_size),
        )
        return [
            DetectedFace(box=FaceBox(int(x), int(y), int(w), int(h)), score=1.0)
            for x, y, w, h in raw_faces
        ]

    def load_image(self, image_input: ImageInput) -> np.ndarray:
        if isinstance(image_input, np.ndarray):
            image = image_input.copy()
        elif isinstance(image_input, (bytes, bytearray)):
            buffer = np.frombuffer(image_input, dtype=np.uint8)
            image = cv2.imdecode(buffer, cv2.IMREAD_COLOR)
        else:
            image = cv2.imread(str(image_input))

        if image is None:
            raise ValueError("Unable to load image.")
        if image.ndim == 2:
            image = cv2.cvtColor(image, cv2.COLOR_GRAY2BGR)
        if image.shape[2] == 4:
            image = cv2.cvtColor(image, cv2.COLOR_BGRA2BGR)
        return image

    @staticmethod
    def cosine_similarity(left: np.ndarray, right: np.ndarray) -> float:
        left_vector = OpenCVFaceEngine._normalize_vector(left)
        right_vector = OpenCVFaceEngine._normalize_vector(right)
        return float(np.dot(left_vector, right_vector))

    def estimate_pose(self, face: DetectedFace) -> PoseEstimate | None:
        if face.landmarks is None:
            return None

        eyes = sorted([face.landmarks.eye_a, face.landmarks.eye_b], key=lambda point: point.x)
        mouths = sorted([face.landmarks.mouth_a, face.landmarks.mouth_b], key=lambda point: point.x)
        left_eye, right_eye = eyes
        left_mouth, right_mouth = mouths
        nose = face.landmarks.nose

        eye_mid_x = (left_eye.x + right_eye.x) / 2
        eye_mid_y = (left_eye.y + right_eye.y) / 2
        mouth_mid_x = (left_mouth.x + right_mouth.x) / 2
        mouth_mid_y = (left_mouth.y + right_mouth.y) / 2
        eye_distance = max(right_eye.x - left_eye.x, 1.0)
        mouth_distance = max(right_mouth.x - left_mouth.x, 1.0)
        vertical_distance = max(mouth_mid_y - eye_mid_y, 1.0)

        yaw = ((nose.x - eye_mid_x) / eye_distance) + ((nose.x - mouth_mid_x) / mouth_distance)
        yaw /= 2.0
        pitch = (nose.y - ((eye_mid_y + mouth_mid_y) / 2.0)) / vertical_distance
        roll = (right_eye.y - left_eye.y) / eye_distance

        label = "front"
        if abs(yaw) < 0.12 and abs(pitch) < 0.10:
            label = "front"
        elif abs(yaw) >= abs(pitch):
            label = "right" if yaw >= 0.15 else "left"
        else:
            label = "down" if pitch >= 0.08 else "up"

        return PoseEstimate(
            label=label,
            yaw=round(float(yaw), 4),
            pitch=round(float(pitch), 4),
            roll=round(float(roll), 4),
        )

    def _initialise_backends(self) -> None:
        if (
            self.config.use_sface_if_available
            and hasattr(cv2, "FaceDetectorYN")
            and hasattr(cv2, "FaceRecognizerSF")
            and self.config.yunet_model_path.exists()
            and self.config.sface_model_path.exists()
        ):
            try:
                self.detector_backend = "opencv_sface"
                self._face_detector = cv2.FaceDetectorYN.create(
                    str(self.config.yunet_model_path),
                    "",
                    (320, 320),
                    self.config.detector_score_threshold,
                    0.3,
                    5000,
                )
                self._face_recognizer = cv2.FaceRecognizerSF.create(
                    str(self.config.sface_model_path),
                    "",
                )
                return
            except cv2.error:
                self.detector_backend = "opencv_haar_hog"
                self._face_detector = None
                self._face_recognizer = None

        cascade_path = Path(cv2.data.haarcascades) / "haarcascade_frontalface_default.xml"
        self._cascade_classifier = cv2.CascadeClassifier(str(cascade_path))
        if self._cascade_classifier.empty():
            raise RuntimeError("OpenCV Haar cascade could not be loaded.")

    @staticmethod
    def _extract_landmarks(raw_face: np.ndarray) -> FaceLandmarks | None:
        if len(raw_face) < 14:
            return None
        return FaceLandmarks(
            eye_a=FacePoint(float(raw_face[4]), float(raw_face[5])),
            eye_b=FacePoint(float(raw_face[6]), float(raw_face[7])),
            nose=FacePoint(float(raw_face[8]), float(raw_face[9])),
            mouth_a=FacePoint(float(raw_face[10]), float(raw_face[11])),
            mouth_b=FacePoint(float(raw_face[12]), float(raw_face[13])),
        )

    def _prepare_face_for_hog(self, image: np.ndarray, face_box: FaceBox) -> np.ndarray:
        face_crop = self._crop_face(image, face_box, padding_ratio=0.18)
        gray_face = cv2.cvtColor(face_crop, cv2.COLOR_BGR2GRAY)
        normalized = cv2.equalizeHist(gray_face)
        return cv2.resize(
            normalized,
            (self.config.hog_face_size, self.config.hog_face_size),
            interpolation=cv2.INTER_AREA,
        )

    @staticmethod
    def _crop_face(image: np.ndarray, face_box: FaceBox, padding_ratio: float) -> np.ndarray:
        height, width = image.shape[:2]
        pad_x = int(face_box.w * padding_ratio)
        pad_y = int(face_box.h * padding_ratio)
        x1 = max(face_box.x - pad_x, 0)
        y1 = max(face_box.y - pad_y, 0)
        x2 = min(face_box.x + face_box.w + pad_x, width)
        y2 = min(face_box.y + face_box.h + pad_y, height)
        return image[y1:y2, x1:x2]

    def _quality_score(
        self,
        blur_score: float,
        brightness: float,
        face_box: FaceBox,
        image_shape: tuple[int, ...],
    ) -> float:
        blur_component = min(1.0, blur_score / max(self.config.blur_threshold, 1.0))
        brightness_midpoint = (self.config.min_brightness + self.config.max_brightness) / 2
        brightness_radius = max(
            (self.config.max_brightness - self.config.min_brightness) / 2,
            1.0,
        )
        brightness_component = max(
            0.0,
            1.0 - abs(brightness - brightness_midpoint) / brightness_radius,
        )
        frame_height, frame_width = image_shape[:2]
        face_fraction = min(
            1.0,
            (face_box.w * face_box.h) / max((frame_width * frame_height) * 0.12, 1.0),
        )
        return round(
            (0.45 * blur_component) + (0.25 * brightness_component) + (0.30 * face_fraction),
            4,
        )

    @staticmethod
    def _normalize_vector(vector: np.ndarray) -> np.ndarray:
        norm = float(np.linalg.norm(vector))
        if norm == 0:
            return vector.astype(np.float32)
        return (vector / norm).astype(np.float32)
