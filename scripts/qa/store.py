"""Storage for questions and answers using JSONL files."""

import fcntl
from pathlib import Path

from qa.models import Answer, Question


class QAStore:
    """Manages questions.jsonl and answers.jsonl files.

    Thread-safe file operations using file locking.
    """

    def __init__(self, qa_dir: Path) -> None:
        """Initialize QA store.

        Args:
            qa_dir: Directory containing questions.jsonl and answers.jsonl
        """
        self.qa_dir = qa_dir
        self.questions_file = qa_dir / "questions.jsonl"
        self.answers_file = qa_dir / "answers.jsonl"

        # Ensure directory exists
        qa_dir.mkdir(parents=True, exist_ok=True)

        # Ensure files exist
        self.questions_file.touch(exist_ok=True)
        self.answers_file.touch(exist_ok=True)

    def add_question(self, question: Question) -> None:
        """Add a question to the store.

        Args:
            question: Question to add
        """
        with open(self.questions_file, "a") as f:
            fcntl.flock(f.fileno(), fcntl.LOCK_EX)
            try:
                f.write(question.to_jsonl() + "\n")
            finally:
                fcntl.flock(f.fileno(), fcntl.LOCK_UN)

    def add_answer(self, answer: Answer) -> None:
        """Add an answer to the store.

        Args:
            answer: Answer to add
        """
        with open(self.answers_file, "a") as f:
            fcntl.flock(f.fileno(), fcntl.LOCK_EX)
            try:
                f.write(answer.to_jsonl() + "\n")
            finally:
                fcntl.flock(f.fileno(), fcntl.LOCK_UN)

    def get_all_questions(self) -> list[Question]:
        """Get all questions.

        Returns:
            List of all questions
        """
        questions: list[Question] = []
        with open(self.questions_file) as f:
            fcntl.flock(f.fileno(), fcntl.LOCK_SH)
            try:
                for line in f:
                    line = line.strip()
                    if line:
                        questions.append(Question.from_jsonl(line))
            finally:
                fcntl.flock(f.fileno(), fcntl.LOCK_UN)
        return questions

    def get_all_answers(self) -> list[Answer]:
        """Get all answers.

        Returns:
            List of all answers
        """
        answers: list[Answer] = []
        with open(self.answers_file) as f:
            fcntl.flock(f.fileno(), fcntl.LOCK_SH)
            try:
                for line in f:
                    line = line.strip()
                    if line:
                        answers.append(Answer.from_jsonl(line))
            finally:
                fcntl.flock(f.fileno(), fcntl.LOCK_UN)
        return answers

    def get_unanswered_questions(self) -> list[Question]:
        """Get questions that haven't been answered yet.

        Returns:
            List of unanswered questions
        """
        questions = self.get_all_questions()
        answers = self.get_all_answers()
        answered_ids = {a.id for a in answers}
        return [q for q in questions if q.id not in answered_ids]

    def get_new_answers(self, since_ids: set[str]) -> list[Answer]:
        """Get answers for questions not in the given set.

        Args:
            since_ids: Set of question IDs already processed

        Returns:
            List of new answers
        """
        answers = self.get_all_answers()
        return [a for a in answers if a.id not in since_ids]

    def get_answer_for_question(self, question_id: str) -> Answer | None:
        """Get the answer for a specific question.

        Args:
            question_id: Question ID to look up

        Returns:
            Answer if found, None otherwise
        """
        answers = self.get_all_answers()
        for answer in answers:
            if answer.id == question_id:
                return answer
        return None

    def generate_question_id(self) -> str:
        """Generate a new unique question ID.

        Returns:
            New question ID (e.g., Q001, Q002)
        """
        questions = self.get_all_questions()
        if not questions:
            return "Q001"

        # Find highest existing ID
        max_num = 0
        for q in questions:
            if q.id.startswith("Q"):
                try:
                    num = int(q.id[1:])
                    max_num = max(max_num, num)
                except ValueError:
                    pass

        return f"Q{max_num + 1:03d}"

    def update_question_message_id(self, question_id: str, message_id: str) -> bool:
        """Update the message_id for a question.

        Args:
            question_id: ID of the question to update
            message_id: Platform-specific message ID (e.g., Slack thread_ts)

        Returns:
            True if question was found and updated, False otherwise
        """
        questions = self.get_all_questions()
        updated = False

        for q in questions:
            if q.id == question_id:
                q.message_id = message_id
                updated = True
                break

        if updated:
            # Rewrite the entire file with updated questions
            with open(self.questions_file, "w") as f:
                fcntl.flock(f.fileno(), fcntl.LOCK_EX)
                try:
                    for q in questions:
                        f.write(q.to_jsonl() + "\n")
                finally:
                    fcntl.flock(f.fileno(), fcntl.LOCK_UN)

        return updated

    def get_question_by_id(self, question_id: str) -> Question | None:
        """Get a question by its ID.

        Args:
            question_id: Question ID to look up

        Returns:
            Question if found, None otherwise
        """
        questions = self.get_all_questions()
        for q in questions:
            if q.id == question_id:
                return q
        return None
