"""QA Bot entry point for `python -m qa`."""

import asyncio
import logging
import os
import sys
from pathlib import Path

# Add scripts/ to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from dotenv import load_dotenv

from qa.bot import QABot
from qa.config import QAConfig

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("qa")


async def main() -> None:
    """Run the QA bot."""
    load_dotenv()

    config = QAConfig.load()
    qa_dir = config.get_qa_dir()

    # Select notifier based on config
    if config.notifier == "slack":
        from qa.notifiers.slack import SlackNotifier
        notifier = SlackNotifier(
            channel=os.environ.get("SLACK_CHANNEL_ID"),
            github_repo=config.github_repo,
        )
    elif config.notifier == "discord":
        from qa.notifiers.discord import DiscordNotifier
        notifier = DiscordNotifier()
    else:
        raise ValueError(f"Unknown platform: {config.notifier}")

    bot = QABot(qa_dir=qa_dir, notifier=notifier)

    logger.info(f"Starting QA Bot (platform={config.notifier})")
    await bot.run()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Shutting down...")
