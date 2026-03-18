"""QA notification platform implementations."""

from qa.notifiers.base import QANotifier

__all__ = ["QANotifier"]

# Conditional imports for platform-specific notifiers
try:
    from qa.notifiers.slack import SLACK_AVAILABLE

    if SLACK_AVAILABLE:
        from qa.notifiers.slack import SlackNotifier  # noqa: F401

        __all__.append("SlackNotifier")
except ImportError:
    pass

try:
    from qa.notifiers.discord import DISCORD_AVAILABLE

    if DISCORD_AVAILABLE:
        from qa.notifiers.discord import DiscordNotifier  # noqa: F401

        __all__.append("DiscordNotifier")
except ImportError:
    pass
