"""Best-effort email sending. Without SMTP configured, forgot-password falls
back to returning the reset code directly in the API response so the flow is
still testable locally — clearly marked as a dev fallback, never silent."""
import asyncio
import smtplib
from email.mime.text import MIMEText

from .config import settings


def smtp_configured() -> bool:
    return bool(settings.smtp_host and settings.smtp_user and settings.smtp_password)


def _send_sync(to: str, subject: str, body: str) -> None:
    msg = MIMEText(body)
    msg["Subject"] = subject
    msg["From"] = settings.smtp_from
    msg["To"] = to
    with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=15) as s:
        s.starttls()
        s.login(settings.smtp_user, settings.smtp_password)
        s.sendmail(settings.smtp_from, [to], msg.as_string())


async def send_reset_code(to: str, code: str) -> bool:
    """Returns True if an email was actually sent."""
    if not smtp_configured():
        return False
    body = (
        f"Your AI Developer Assistant password reset code is: {code}\n\n"
        "Enter it in the app's 'Reset password' screen. It expires in 30 minutes.\n"
        "If you didn't request this, you can ignore this email."
    )
    try:
        await asyncio.to_thread(_send_sync, to, "Reset your password", body)
        return True
    except Exception:
        return False
