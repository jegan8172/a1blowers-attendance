from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import letter
from reportlab.lib.colors import HexColor, white
from reportlab.lib.utils import ImageReader
from reportlab.pdfbase.pdfmetrics import stringWidth
from PIL import Image
import os

ROOT = r"C:\Users\sahan\OneDrive\Desktop\A1 backup\Godigital_attendance"
OUT = os.path.join(ROOT, "output", "pdf", "godigital_attendance_sales_report_expanded.pdf")
W, H = letter

NAVY = HexColor("#081B3C")
BLUE = HexColor("#1769E0")
SKY = HexColor("#EAF2FF")
MUTED = HexColor("#64748B")
LINE = HexColor("#DCE4F0")
PAGE = HexColor("#F7F9FD")
GREEN = HexColor("#0B9F6B")
ORANGE = HexColor("#F97316")

IMG = {
    "login": r"C:\Users\sahan\AppData\Local\Temp\codex-clipboard-bef7a8a1-408a-4d79-af15-b5cba96a1c6f.png",
    "admin_dashboard": r"C:\Users\sahan\AppData\Local\Temp\codex-clipboard-be37fea7-93f7-47a0-a2f0-4d521f21449b.png",
    "employees": r"C:\Users\sahan\AppData\Local\Temp\codex-clipboard-6a9c9edf-6002-4a80-83bd-bb916575a870.png",
    "clock_logs": r"C:\Users\sahan\AppData\Local\Temp\codex-clipboard-9addac5f-2816-42e5-bb39-0501e193a794.png",
    "approvals": r"C:\Users\sahan\AppData\Local\Temp\codex-clipboard-19f3d5f9-9f6e-4353-aacd-c5a7fa43a1ec.png",
    "payroll": r"C:\Users\sahan\AppData\Local\Temp\codex-clipboard-6087b666-81b8-4f18-bd4e-c2341a09e7c8.png",
    "admin_tracking": r"C:\Users\sahan\AppData\Local\Temp\codex-clipboard-ef5e8f35-7835-4542-8f80-0fa00f5faa43.png",
    "chat": r"C:\Users\sahan\AppData\Local\Temp\codex-clipboard-88b9c5be-c0bf-4a70-b7eb-c731efbf0330.png",
    "employee_dashboard": r"C:\Users\sahan\AppData\Local\Temp\codex-clipboard-1fb15ac3-54ee-4ffd-9903-af31353c0ff9.png",
    "employee_attendance": r"C:\Users\sahan\AppData\Local\Temp\codex-clipboard-dc4d2b9c-06f2-451b-9776-f3c0c708e971.png",
    "employee_clock": r"C:\Users\sahan\AppData\Local\Temp\codex-clipboard-8dca547c-7843-490b-bc5d-7802aba5c5a2.png",
    "employee_salary": r"C:\Users\sahan\AppData\Local\Temp\codex-clipboard-bf687f40-7d61-4590-82e3-1721ae1401fc.png",
    "leave": r"C:\Users\sahan\AppData\Local\Temp\codex-clipboard-755c18d0-db56-4bf0-92d0-cb755159d2c4.png",
    "permission": r"C:\Users\sahan\AppData\Local\Temp\codex-clipboard-3aecc9a6-65b3-4e2d-bdb3-58136ece1a4c.png",
    "employee_tracking": r"C:\Users\sahan\AppData\Local\Temp\codex-clipboard-e877df63-1167-4877-9166-9bf46277bb71.png",
    "settings": r"C:\Users\sahan\AppData\Local\Temp\codex-clipboard-d446e42d-b731-4260-ae87-0922f05601c6.png",
    "extra_hours": r"C:\Users\sahan\AppData\Local\Temp\codex-clipboard-7558a90d-86d9-4dd8-a6d6-8c8bd33c8cc7.png",
}


def wrap(c, text, font, size, width):
    words, lines, line = text.split(), [], ""
    for word in words:
        candidate = (line + " " + word).strip()
        if stringWidth(candidate, font, size) <= width or not line:
            line = candidate
        else:
            lines.append(line)
            line = word
    if line:
        lines.append(line)
    return lines


def paragraph(c, text, x, y, width, size=10, color=MUTED, leading=None, font="Helvetica"):
    leading = leading or size * 1.45
    c.setFont(font, size)
    c.setFillColor(color)
    for line in wrap(c, text, font, size, width):
        c.drawString(x, y, line)
        y -= leading
    return y


def rounded(c, x, y, w, h, fill, radius=12, stroke=None):
    c.setFillColor(fill)
    if stroke:
        c.setStrokeColor(stroke)
        c.setLineWidth(0.7)
    else:
        c.setStrokeColor(fill)
    c.roundRect(x, y, w, h, radius, fill=1, stroke=1 if stroke else 0)


def header(c, title, eyebrow=None, page=None):
    c.setFillColor(white)
    c.rect(0, H - 64, W, 64, fill=1, stroke=0)
    c.setStrokeColor(LINE)
    c.line(34, H - 64, W - 34, H - 64)
    c.setFillColor(NAVY)
    c.setFont("Helvetica-Bold", 14)
    c.drawString(34, H - 37, "GoDigital")
    c.setFillColor(BLUE)
    c.setFont("Helvetica-Bold", 9)
    c.drawString(104, H - 37, "ATTENDANCE")
    if eyebrow:
        c.setFillColor(MUTED)
        c.setFont("Helvetica", 8)
        c.drawRightString(W - 34, H - 37, eyebrow.upper())
    c.setFillColor(NAVY)
    c.setFont("Helvetica-Bold", 23)
    c.drawString(34, H - 104, title)
    if page:
        footer(c, page)


def footer(c, page):
    c.setStrokeColor(LINE)
    c.line(34, 30, W - 34, 30)
    c.setFillColor(MUTED)
    c.setFont("Helvetica", 8)
    c.drawString(34, 17, "GoDigital Attendance and Workforce Management")
    c.drawRightString(W - 34, 17, str(page))


def image_fit(c, path, x, y, w, h, caption=None):
    im = Image.open(path)
    iw, ih = im.size
    scale = min(w / iw, h / ih)
    dw, dh = iw * scale, ih * scale
    px, py = x + (w - dw) / 2, y + (h - dh) / 2
    rounded(c, x, y, w, h, white, 12, LINE)
    c.drawImage(ImageReader(im), px, py, dw, dh, preserveAspectRatio=True, mask='auto')
    if caption:
        c.setFillColor(NAVY)
        c.setFont("Helvetica-Bold", 9)
        c.drawString(x + 10, y - 14, caption)


def image_crop(c, path, x, y, w, h, crop, caption=None):
    im = Image.open(path).crop(crop)
    iw, ih = im.size
    scale = max(w / iw, h / ih)
    dw, dh = iw * scale, ih * scale
    px, py = x + (w - dw) / 2, y + (h - dh) / 2
    rounded(c, x, y, w, h, white, 12, LINE)
    c.saveState()
    clip = c.beginPath()
    clip.rect(x, y, w, h)
    c.clipPath(clip, stroke=0, fill=0)
    c.drawImage(ImageReader(im), px, py, dw, dh, preserveAspectRatio=True, mask='auto')
    c.restoreState()
    if caption:
        c.setFillColor(NAVY)
        c.setFont("Helvetica-Bold", 9)
        c.drawString(x + 10, y - 14, caption)


def bullets(c, items, x, y, width):
    for title, body, color in items:
        c.setFillColor(color)
        c.circle(x + 5, y + 2, 4, fill=1, stroke=0)
        c.setFillColor(NAVY)
        c.setFont("Helvetica-Bold", 10)
        c.drawString(x + 18, y - 1, title)
        y -= 15
        y = paragraph(c, body, x + 18, y, width - 18, 9, MUTED)
        y -= 10
    return y


def title_page(c):
    c.setFillColor(NAVY)
    c.rect(0, 0, W, H, fill=1, stroke=0)
    c.setFillColor(BLUE)
    c.circle(W - 32, H - 28, 120, fill=1, stroke=0)
    c.setFillColor(HexColor("#0D2D62"))
    c.circle(W - 60, H - 85, 90, fill=1, stroke=0)
    c.setFillColor(white)
    c.setFont("Helvetica-Bold", 18)
    c.drawString(44, H - 75, "GoDigital")
    c.setFillColor(HexColor("#8FB9FF"))
    c.setFont("Helvetica-Bold", 9)
    c.drawString(44, H - 92, "ATTENDANCE AND WORKFORCE MANAGEMENT")
    c.setFillColor(white)
    c.setFont("Helvetica-Bold", 32)
    c.drawString(44, H - 178, "Attendance and")
    c.drawString(44, H - 218, "workforce operations")
    c.setFont("Helvetica", 15)
    c.setFillColor(HexColor("#C8D8F2"))
    c.drawString(44, H - 251, "A sales overview for modern people operations")
    rounded(c, 44, H - 340, 274, 82, HexColor("#102A55"), 14)
    c.setFillColor(white)
    c.setFont("Helvetica-Bold", 12)
    c.drawString(62, H - 289, "One connected platform")
    c.setFillColor(HexColor("#C8D8F2"))
    c.setFont("Helvetica", 10)
    c.drawString(62, H - 309, "Attendance, approvals, payroll visibility,")
    c.drawString(62, H - 324, "field tracking, employee self-service and chat.")
    image_fit(c, IMG["admin_dashboard"], 44, 76, W - 88, 205)
    c.setFillColor(HexColor("#AFCBFF"))
    c.setFont("Helvetica", 8)
    c.drawRightString(W - 44, 45, "Marketing sales report | Product screens shown for illustration")
    c.showPage()


def overview_page(c, page):
    header(c, "A single source of truth", "Platform overview", page)
    paragraph(c, "GoDigital brings the daily employee journey and the operations team into one connected workspace. Teams can move from attendance data to action without relying on separate registers, spreadsheets and follow-up messages.", 34, H - 132, W - 68, 11, MUTED)
    cards = [
        ("OPERATIONS", "Attendance", "Central attendance views, clock logs and exception visibility.", BLUE),
        ("PEOPLE", "Approvals", "Leave, permission, device and extra-hours workflows in one place.", GREEN),
        ("FIELD", "Live tracking", "Office and field activity views designed for distributed teams.", ORANGE),
        ("EMPLOYEE", "Self-service", "Clocking, requests, salary visibility and team communication.", HexColor("#7C3AED")),
    ]
    x, y, cw, ch = 34, H - 300, 128, 122
    for i, (eyebrow, title, body, color) in enumerate(cards):
        px = x + (i % 2) * (cw + 18)
        py = y - (i // 2) * (ch + 18)
        rounded(c, px, py, cw, ch, white, 13, LINE)
        c.setFillColor(color)
        c.circle(px + 22, py + ch - 24, 10, fill=1, stroke=0)
        c.setFillColor(MUTED)
        c.setFont("Helvetica-Bold", 7)
        c.drawString(px + 13, py + 72, eyebrow)
        c.setFillColor(NAVY)
        c.setFont("Helvetica-Bold", 13)
        c.drawString(px + 13, py + 52, title)
        paragraph(c, body, px + 13, py + 35, cw - 26, 8.2, MUTED)
    image_crop(c, IMG["login"], 322, 137, 255, 340, (930, 170, 1435, 785), "Secure role based entry point")
    c.showPage()


def highlights_page(c, page):
    header(c, "Platform highlights", "What buyers can see", page)
    paragraph(c, "Use this page as a quick capability map during a first conversation. Each workspace is designed to support a connected part of workforce operations while keeping the experience clear for the people using it every day.", 34, H - 132, W - 68, 10.3, MUTED)
    items = [
        ("Attendance", "Monthly attendance, working days and exceptions", BLUE),
        ("Clock logs", "Check-in, check-out, worked time and status", GREEN),
        ("Employees", "Employee directory, work mode and status", ORANGE),
        ("Approvals", "Leave, permission, devices and extra hours", HexColor("#7C3AED")),
        ("Payroll", "Payroll rows, deductions, net pay and status", BLUE),
        ("Tracking", "Office and field work activity views", GREEN),
        ("Self service", "Calendar, requests, salary and clocking", ORANGE),
        ("Communication", "Attendance enabled employee and admin chat", HexColor("#7C3AED")),
    ]
    for i, (title, body, color) in enumerate(items):
        col, row = i % 2, i // 2
        x = 34 + col * 274
        y = H - 300 - row * 113
        rounded(c, x, y, 258, 94, white, 12, LINE)
        c.setFillColor(color)
        c.circle(x + 20, y + 66, 8, fill=1, stroke=0)
        c.setFillColor(NAVY)
        c.setFont("Helvetica-Bold", 12)
        c.drawString(x + 39, y + 61, title)
        paragraph(c, body, x + 16, y + 38, 224, 8.8, MUTED)
    footer(c, page)
    c.showPage()


def feature_page(c, page, title, eyebrow, copy, image, caption, points):
    header(c, title, eyebrow, page)
    y = paragraph(c, copy, 34, H - 132, W - 68, 10.5, MUTED)
    image_fit(c, image, 34, 280, W - 68, 275, caption)
    bullets(c, points, 34, 240, W - 68)
    c.showPage()


def employee_page(c, page):
    header(c, "Employee self service", "Employee experience", page)
    paragraph(c, "A clear employee workspace helps people act on their attendance information without waiting for manual follow-up. The interface brings daily work status, requests, historical records and communication into familiar flows.", 34, H - 132, W - 68, 10.5, MUTED)
    image_fit(c, IMG["employee_dashboard"], 34, 321, W - 68, 242, "Employee dashboard")
    image_fit(c, IMG["employee_attendance"], 34, 72, 266, 224, "Attendance calendar")
    image_fit(c, IMG["employee_clock"], 312, 72, 266, 224, "Clock in and clock out")
    c.showPage()


def payroll_workflow_page(c, page):
    header(c, "Attendance-powered payroll", "Payroll value story", page)
    paragraph(c, "Payroll conversations are stronger when buyers can see how daily workforce data becomes a reviewable pay outcome. GoDigital brings the relevant attendance and payroll fields into a clear operational flow.", 34, H - 132, W - 68, 10.5, MUTED)
    steps = [
        ("01", "Set work rules", "Working days, attendance rules and employee settings establish the operational context."),
        ("02", "Capture time", "Clock activity and attendance records make day level work status visible."),
        ("03", "Review payroll", "Payroll rows show salary, working days, paid days, absence, deductions and net pay."),
        ("04", "Share visibility", "Employees can view a dedicated salary workspace alongside their other self-service tools."),
    ]
    y = H - 300
    for i, (number, title, body) in enumerate(steps):
        x = 34 + (i % 2) * 274
        py = y - (i // 2) * 118
        rounded(c, x, py, 258, 102, SKY if i in (0, 2) else white, 12, LINE)
        c.setFillColor(BLUE)
        c.setFont("Helvetica-Bold", 11)
        c.drawString(x + 14, py + 76, number)
        c.setFillColor(NAVY)
        c.setFont("Helvetica-Bold", 12)
        c.drawString(x + 52, py + 76, title)
        paragraph(c, body, x + 14, py + 54, 228, 8.7, MUTED)
    rounded(c, 34, 140, W - 68, 72, NAVY, 13)
    c.setFillColor(white)
    c.setFont("Helvetica-Bold", 13)
    c.drawString(50, 181, "Payroll review made easier to explain")
    c.setFillColor(HexColor("#C8D8F2"))
    c.setFont("Helvetica", 9.5)
    c.drawString(50, 160, "Use the payroll screen to discuss the practical fields finance and operations teams need to review.")
    footer(c, page)
    c.showPage()


def use_case_page(c, page):
    header(c, "Where GoDigital fits", "Use cases", page)
    paragraph(c, "The platform is relevant wherever teams need a clearer connection between people, time, approvals and day to day workforce operations. Position the demonstration around the prospect's operating model.", 34, H - 132, W - 68, 10.5, MUTED)
    cases = [
        ("Office based teams", "Attendance, clock logs, approvals and payroll review for teams working from one or more office locations.", BLUE),
        ("Field and sales teams", "Live tracking and employee activity views for people who work away from a central office.", GREEN),
        ("Growing operations", "A structured employee directory and consistent request flows as the workforce and approval load increases.", ORANGE),
        ("Mixed workforce models", "One workspace for office, field and hybrid team visibility, paired with employee self-service.", HexColor("#7C3AED")),
    ]
    for i, (title, body, color) in enumerate(cases):
        x = 34 + (i % 2) * 274
        y = H - 320 - (i // 2) * 152
        rounded(c, x, y, 258, 132, white, 13, LINE)
        c.setFillColor(color)
        c.circle(x + 23, y + 103, 10, fill=1, stroke=0)
        c.setFillColor(NAVY)
        c.setFont("Helvetica-Bold", 13)
        c.drawString(x + 44, y + 98, title)
        paragraph(c, body, x + 17, y + 70, 222, 9.2, MUTED)
    rounded(c, 34, 98, W - 68, 82, HexColor("#EEF5FF"), 13, LINE)
    c.setFillColor(NAVY)
    c.setFont("Helvetica-Bold", 12)
    c.drawString(50, 144, "Recommended discovery questions")
    c.setFillColor(MUTED)
    c.setFont("Helvetica", 9.3)
    c.drawString(50, 123, "How are attendance records reviewed today? Which requests create the most follow-up? Which employees work in the field?")
    footer(c, page)
    c.showPage()


def action_page(c, page):
    header(c, "Sales conversation guide", "For the marketing team", page)
    paragraph(c, "Start with the operational problem a prospect already understands, then show the relevant workspace. Keep the conversation focused on practical outcomes and configure the demonstration around the prospect's workforce model.", 34, H - 132, W - 68, 10.5, MUTED)
    rows = [
        ("Manual attendance follow up", "Show attendance dashboard, clock logs and automated attendance update cards."),
        ("Slow manager approvals", "Show the approvals workspace and employee leave or permission request screens."),
        ("Field team visibility", "Show office and field tracking views with current activity and location context."),
        ("Employee self service", "Show clocking, calendar, leave, permission, salary and chat from the employee workspace."),
        ("Payroll preparation", "Show payroll-ready employee rows, attendance inputs and status visibility."),
    ]
    y = H - 185
    for i, (problem, response) in enumerate(rows):
        rounded(c, 34, y - 54, W - 68, 62, white, 10, LINE)
        c.setFillColor(BLUE)
        c.setFont("Helvetica-Bold", 9)
        c.drawString(48, y - 14, "0" + str(i + 1))
        c.setFillColor(NAVY)
        c.setFont("Helvetica-Bold", 11)
        c.drawString(79, y - 14, problem)
        paragraph(c, response, 79, y - 30, W - 128, 9, MUTED)
        y -= 77
    rounded(c, 34, 74, W - 68, 72, NAVY, 13)
    c.setFillColor(white)
    c.setFont("Helvetica-Bold", 14)
    c.drawString(50, 112, "Next step: tailor the live demonstration")
    c.setFillColor(HexColor("#C8D8F2"))
    c.setFont("Helvetica", 9.5)
    c.drawString(50, 92, "Use the prospect's shift rules, approval process and workforce model to make the value tangible.")
    c.showPage()


def build():
    c = canvas.Canvas(OUT, pagesize=letter, pageCompression=1)
    c.setTitle("GoDigital Attendance Workforce Management Sales Report")
    title_page(c)
    overview_page(c, 2)
    highlights_page(c, 3)
    feature_page(c, 4, "Command centre for attendance", "Admin dashboard", "Give administrators an at-a-glance view of working days, active employees, present staff, attendance exceptions and outstanding approvals. Quick actions make the next step visible from the same workspace.", IMG["admin_dashboard"], "Admin attendance dashboard", [("Daily visibility", "See key attendance and approval signals together.", BLUE), ("Operational shortcuts", "Move directly to time rules, calendar management and approval work.", GREEN)])
    feature_page(c, 5, "Employee and attendance operations", "Admin workspace", "Employee records and attendance views help operations teams find the right person, filter the workforce and review attendance information in a consistent interface.", IMG["employees"], "Employee directory and workforce filters", [("Structured records", "Review employee identity, department, work mode and current status.", BLUE), ("Attendance visibility", "Bring month level attendance data and exception details into the operational workflow.", ORANGE)])
    feature_page(c, 6, "Clock log clarity", "Daily operations", "Clock logs provide a focused view of check-ins, check-outs, worked time and status for the selected date. This gives teams a practical starting point for attendance review and follow-up.", IMG["clock_logs"], "Clock log review", [("Searchable daily view", "Locate employees and review time activity from one screen.", BLUE), ("Exception awareness", "Surface active and late status alongside the working record.", ORANGE)])
    feature_page(c, 7, "Approvals that move work forward", "Requests and policies", "A central approvals workspace helps managers review employee requests with the relevant request details close at hand. The sales story is simple: fewer status chases and a clearer decision trail.", IMG["approvals"], "Approval queue and request detail", [("Unified queue", "Review leave, permissions, device requests and more in one workflow.", BLUE), ("Decision context", "Open the selected request and act with employee details visible.", GREEN)])
    feature_page(c, 8, "Policies and workspace control", "Configuration", "Settings bring time rules, calendar management, employee access, payroll policy, office locations, tracking templates and reminder preferences into one organised control area.", IMG["settings"], "Administrative settings workspace", [("Operational rules", "Maintain the core policies that shape attendance and employee workflows.", BLUE), ("Configurable modules", "Bring payroll, tracking, reminders and employee access controls into one place.", GREEN)])
    feature_page(c, 9, "Payroll ready visibility", "Payroll workspace", "Bring payroll review into a clear operational workspace. The payroll table makes employee salary, per day salary, working days, paid days, absence, deductions, net pay and current status visible together.", IMG["payroll"], "Payroll review workspace", [("Payroll review fields", "Review the practical salary and attendance inputs in one employee level view.", BLUE), ("Clear review state", "See payroll rows and current processing status before the next finance action.", ORANGE)])
    payroll_workflow_page(c, 10)
    feature_page(c, 11, "Salary visibility for employees", "Employee salary workspace", "The employee experience includes a dedicated salary page with updated salary, earned to date information and recent payslip status. This supports clearer employee access to their own payroll information.", IMG["employee_salary"], "Employee salary overview", [("Employee access", "Keep personal salary information inside the same familiar employee workspace.", BLUE), ("Clear conversation", "Use a dedicated salary view to support payroll related employee queries.", GREEN)])
    feature_page(c, 12, "Field and office tracking", "Live tracking", "For organisations with mobile or field based teams, GoDigital provides distinct office and field views. The map based workspace makes current activity easier to review alongside the employee list.", IMG["admin_tracking"], "Admin live tracking workspace", [("Work mode context", "Differentiate office, home and field activity.", BLUE), ("Activity visibility", "Review active team members and their latest available location context.", GREEN)])
    employee_page(c, 13)
    feature_page(c, 14, "Requests and employee information", "Self service", "Employees can submit leave and permission requests through guided forms and view their information in the same workspace. This supports a more transparent employee experience while keeping workflows connected to approvals.", IMG["leave"], "Employee leave request", [("Guided requests", "Collect leave type, duration, dates and reason in a clear flow.", BLUE), ("Permission workflow", "Support time based permission requests alongside attendance activity.", HexColor("#7C3AED"))])
    feature_page(c, 15, "Extra hours with clear records", "Employee time", "The employee extra-hours view keeps additional work time visible as part of attendance records. This creates a straightforward discussion point for organisations that track time beyond the planned shift.", IMG["extra_hours"], "Employee extra hours workspace", [("Monthly overview", "View recorded extra hours and the selected month from one screen.", BLUE), ("Attendance context", "Keep additional time connected to the wider attendance experience.", ORANGE)])
    feature_page(c, 16, "Attendance chat and timely updates", "Connected communication", "In-app chat gives employees and administrators a direct channel for conversation. Attendance system cards can keep relevant updates visible inside the same work context.", IMG["chat"], "Attendance enabled conversation", [("Contextual updates", "Surface attendance updates in the conversation flow.", ORANGE), ("Direct communication", "Support practical employee and administrator conversations.", BLUE)])
    feature_page(c, 17, "Employee live tracking", "Field employee experience", "Employees in field roles can use a dedicated live tracking workspace that shows current mode, current status, map context and activity history. This helps connect field work with workforce operations.", IMG["employee_tracking"], "Employee field tracking workspace", [("Current state", "Make the selected work mode and latest update visible to the employee.", GREEN), ("Activity history", "Keep recent tracking events and comments in context.", BLUE)])
    use_case_page(c, 18)
    action_page(c, 19)
    c.save()


if __name__ == "__main__":
    build()
