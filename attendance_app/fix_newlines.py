def fix_newlines():
    filepath = r"c:\Student Management System\attendance_app\lib\screens\admin_page.dart"
    with open(filepath, 'r', encoding='utf-8') as f:
        text = f.read()

    text = text.replace("• ${a['department']}\nIn:", "• ${a['department']}\\nIn:")
    text = text.replace("• ${lr['department']}\n'", "• ${lr['department']}\\n'")
    text = text.replace("• $duration\n'", "• $duration\\n'")
    text = text.replace("$dateLabel\n'", "$dateLabel\\n'")
    text = text.replace("• Dept: ${s['department']}\n'", "• Dept: ${s['department']}\\n'")
    text = text.replace("• $department\nSalary:", "• $department\\nSalary:")

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(text)

if __name__ == '__main__':
    fix_newlines()
