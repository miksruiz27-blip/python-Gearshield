import json
import sys

PROTECTED_SUBSTRINGS = [
    "python GearShield/data/",
    "python GearShield\\data\\",
    "external_datasets/",
    "external_datasets\\",
    "dev-clean_mini.tar.gz",
]
PROTECTED_EXTENSIONS = (".joblib", ".onnx")


def is_protected(path):
    if not path:
        return False
    normalized = path.replace("\\", "/")
    for sub in PROTECTED_SUBSTRINGS:
        if sub.replace("\\", "/") in normalized:
            return True
    return normalized.lower().endswith(PROTECTED_EXTENSIONS)


def main():
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return
    tool_input = payload.get("tool_input", {})
    path = tool_input.get("file_path") or tool_input.get("path") or ""
    if is_protected(path):
        print(
            json.dumps(
                {
                    "hookSpecificOutput": {
                        "hookEventName": "PreToolUse",
                        "permissionDecision": "deny",
                        "permissionDecisionReason": (
                            "Blocked by CLAUDE.md policy: data/, external_datasets/, "
                            "dataset archives, and .joblib/.onnx model artifacts must "
                            "not be modified unless the user explicitly asked for it "
                            "in this message. If they did, tell them to say so "
                            "explicitly or use /retrain-model."
                        ),
                    }
                }
            )
        )


if __name__ == "__main__":
    main()
