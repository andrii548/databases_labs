from http import HTTPStatus
from flask import jsonify, make_response
from app.my_project import db


def _extract_mysql_error(exc):
    """Extract MySQL numeric error code and message from SQLAlchemy/PyMySQL exceptions."""
    orig = getattr(exc, "orig", exc)
    args = getattr(orig, "args", ())
    error_code = args[0] if len(args) >= 1 and isinstance(args[0], int) else None
    error_msg = str(args[1]) if len(args) >= 2 else str(orig)
    return error_code, error_msg


def handle_db_error(e):
    """Rollback the current DB session and map MySQL error codes to HTTP JSON responses."""
    try:
        db.session.rollback()
    except Exception:
        pass

    error_code, error_msg = _extract_mysql_error(e)
    msg_lower = error_msg.lower()

    if error_code == 1062:
        status = HTTPStatus.CONFLICT
    elif error_code in (1451, 1452):
        status = HTTPStatus.CONFLICT
    elif error_code == 1644:
        if "not found" in msg_lower:
            status = HTTPStatus.NOT_FOUND
        elif "forbidden" in msg_lower:
            status = HTTPStatus.FORBIDDEN
        elif "integrity error" in msg_lower:
            status = HTTPStatus.CONFLICT
        else:
            status = HTTPStatus.UNPROCESSABLE_ENTITY
    elif error_code in (1366, 1265, 1406):
        status = HTTPStatus.BAD_REQUEST
    else:
        status = HTTPStatus.INTERNAL_SERVER_ERROR

    payload = {"error": error_msg}
    if error_code is not None:
        payload["code"] = error_code

    return make_response(jsonify(payload), status)
