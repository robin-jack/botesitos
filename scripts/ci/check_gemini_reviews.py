#!/usr/bin/env python3
"""
check_gemini_reviews.py

Polls a GitHub PR for review comments from Gemini Code Assist (or other specified bots).
Outputs structured JSON for consumption by OpenCode or CI systems.

Usage:
    python check_gemini_reviews.py --pr-number 123
    python check_gemini_reviews.py --pr-number 123 --timeout 600 --poll-interval 20
    python check_gemini_reviews.py --pr-number 123 --output gemini_comments.json

Environment Variables:
    GITHUB_TOKEN    Required. GitHub personal access token or GITHUB_TOKEN in Actions.
    GITHUB_REPOSITORY  Optional. "owner/repo" format. Auto-detected from git remote if absent.
    GITHUB_PR_NUMBER   Optional. PR number. Overrides --pr-number if set.

Exit Codes:
    0   Comments found (or --dry-run mode).
    1   No comments found within timeout.
    2   Error (bad args, auth failure, network issue).
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
from typing import Any, Optional

try:
    import requests
except ImportError:
    print("Error: 'requests' is required. Install it with: pip install requests", file=sys.stderr)
    sys.exit(2)


class GitHubAPI:
    def __init__(self, token: str):
        self.session = requests.Session()
        self.session.headers.update({
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "opencode-gemini-checker/1.0",
        })
        self.base_url = "https://api.github.com"

    def get(self, endpoint: str) -> Optional[Any]:
        url = f"{self.base_url}{endpoint}" if not endpoint.startswith("http") else endpoint
        try:
            resp = self.session.get(url, timeout=30)
            resp.raise_for_status()
            return resp.json()
        except requests.RequestException as e:
            print(f"API error: {e}", file=sys.stderr)
            return None


def detect_repo() -> tuple[str, str]:
    """Try to detect owner/repo from git remote origin."""
    try:
        result = subprocess.run(
            ["git", "remote", "get-url", "origin"],
            capture_output=True, text=True, check=True, timeout=10
        )
        url = result.stdout.strip()
        # Handle https://github.com/owner/repo.git or git@github.com:owner/repo.git
        if url.startswith("https://github.com/"):
            parts = url.replace("https://github.com/", "").replace(".git", "").split("/")
        elif url.startswith("git@github.com:"):
            parts = url.replace("git@github.com:", "").replace(".git", "").split("/")
        else:
            return ("", "")
        if len(parts) >= 2:
            return (parts[0], parts[1])
    except Exception:
        pass
    return ("", "")


def fetch_comments(gh: GitHubAPI, owner: str, repo: str, pr_number: int) -> list[dict]:
    """
    Fetch all review comments, issue comments, and reviews for a PR.
    Returns a flat list of comment dicts with unified schema.
    """
    comments: list[dict] = []

    # 1. Review comments (inline on diffs)
    review_comments = gh.get(f"/repos/{owner}/{repo}/pulls/{pr_number}/comments")
    if isinstance(review_comments, list):
        for c in review_comments:
            comments.append({
                "id": c.get("id"),
                "user": c.get("user", {}).get("login", ""),
                "body": c.get("body", ""),
                "path": c.get("path", ""),
                "line": c.get("line"),
                "original_line": c.get("original_line"),
                "commit_id": c.get("commit_id", ""),
                "created_at": c.get("created_at", ""),
                "updated_at": c.get("updated_at", ""),
                "html_url": c.get("html_url", ""),
                "type": "review_comment",
                "pull_request_review_id": c.get("pull_request_review_id"),
            })

    # 2. Issue comments (general PR conversation)
    issue_comments = gh.get(f"/repos/{owner}/{repo}/issues/{pr_number}/comments")
    if isinstance(issue_comments, list):
        for c in issue_comments:
            comments.append({
                "id": c.get("id"),
                "user": c.get("user", {}).get("login", ""),
                "body": c.get("body", ""),
                "path": None,
                "line": None,
                "original_line": None,
                "commit_id": None,
                "created_at": c.get("created_at", ""),
                "updated_at": c.get("updated_at", ""),
                "html_url": c.get("html_url", ""),
                "type": "issue_comment",
                "pull_request_review_id": None,
            })

    # 3. Reviews (summary reviews, e.g. "CHANGES_REQUESTED" with body)
    reviews = gh.get(f"/repos/{owner}/{repo}/pulls/{pr_number}/reviews")
    if isinstance(reviews, list):
        for r in reviews:
            body = r.get("body", "")
            if body:
                comments.append({
                    "id": r.get("id"),
                    "user": r.get("user", {}).get("login", ""),
                    "body": body,
                    "path": None,
                    "line": None,
                    "original_line": None,
                    "commit_id": r.get("commit_id", ""),
                    "created_at": r.get("submitted_at", ""),
                    "updated_at": r.get("submitted_at", ""),
                    "html_url": r.get("html_url", ""),
                    "type": "review",
                    "state": r.get("state", ""),
                    "pull_request_review_id": r.get("id"),
                })

    return comments


def filter_bot_comments(comments: list[dict], bot_regex: re.Pattern) -> list[dict]:
    """Filter comments where the user login matches the bot regex."""
    return [c for c in comments if bot_regex.search(c.get("user", ""))]


def classify_comments(comments: list[dict]) -> dict:
    """Classify comments into action_required vs suggestions for summary."""
    action_keywords = re.compile(
        r"\b(must|should|need to|fix|error|bug|broken|incorrect|critical|urgent|required)\b",
        re.IGNORECASE,
    )
    suggestion_keywords = re.compile(
        r"\b(consider|suggest|maybe|could|might|optional|nit|style|improvement|recommend)\b",
        re.IGNORECASE,
    )

    action_required = 0
    suggestions = 0

    for c in comments:
        body = c.get("body", "")
        if action_keywords.search(body):
            action_required += 1
        elif suggestion_keywords.search(body):
            suggestions += 1
        else:
            # Default to suggestion if no strong signal
            suggestions += 1

    return {
        "total": len(comments),
        "action_required": action_required,
        "suggestions": suggestions,
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Poll a GitHub PR for Gemini Code Assist review comments.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --pr-number 42
  %(prog)s --pr-number 42 --timeout 600 --poll-interval 15
  %(prog)s --owner myorg --repo myrepo --pr-number 5 --output results.json
        """,
    )
    parser.add_argument("--pr-number", type=int, help="Pull request number to check.")
    parser.add_argument("--owner", type=str, default="", help="Repository owner/org.")
    parser.add_argument("--repo", type=str, default="", help="Repository name.")
    parser.add_argument(
        "--bot-regex",
        type=str,
        default="gemini|google-cloud-build",
        help="Regex to match bot usernames (default: 'gemini|google-cloud-build').",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=300,
        help="Maximum seconds to poll (default: 300).",
    )
    parser.add_argument(
        "--poll-interval",
        type=int,
        default=30,
        help="Seconds between polls (default: 30).",
    )
    parser.add_argument(
        "--output",
        type=str,
        default="",
        help="Write JSON results to this file instead of stdout.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would be done without polling.",
    )
    parser.add_argument(
        "--require-min-comments",
        type=int,
        default=1,
        help="Minimum number of bot comments to consider 'done' (default: 1).",
    )

    args = parser.parse_args()

    # Resolve PR number
    pr_number = args.pr_number
    if not pr_number:
        pr_number_env = os.environ.get("GITHUB_PR_NUMBER", "")
        if pr_number_env:
            try:
                pr_number = int(pr_number_env)
            except ValueError:
                print(f"Error: Invalid GITHUB_PR_NUMBER: {pr_number_env}", file=sys.stderr)
                return 2

    if not pr_number:
        print("Error: --pr-number is required (or set GITHUB_PR_NUMBER).", file=sys.stderr)
        return 2

    # Resolve owner/repo
    owner, repo = args.owner, args.repo
    if not owner or not repo:
        repo_env = os.environ.get("GITHUB_REPOSITORY", "")
        if repo_env and "/" in repo_env:
            parts = repo_env.split("/", 1)
            owner = owner or parts[0]
            repo = repo or parts[1]

    if not owner or not repo:
        git_owner, git_repo = detect_repo()
        owner = owner or git_owner
        repo = repo or git_repo

    if not owner or not repo:
        print("Error: Could not detect owner/repo. Use --owner/--repo or set GITHUB_REPOSITORY.", file=sys.stderr)
        return 2

    # Resolve token
    token = os.environ.get("GITHUB_TOKEN", "")
    if not token:
        print("Error: GITHUB_TOKEN environment variable is required.", file=sys.stderr)
        return 2

    bot_regex = re.compile(args.bot_regex, re.IGNORECASE)

    if args.dry_run:
        print(f"[DRY RUN] Would poll PR #{pr_number} in {owner}/{repo}")
        print(f"[DRY RUN] Bot regex: {args.bot_regex}")
        print(f"[DRY RUN] Timeout: {args.timeout}s, Interval: {args.poll_interval}s")
        return 0

    gh = GitHubAPI(token)
    start_time = time.time()
    attempt = 0

    print(f"Polling PR #{pr_number} in {owner}/{repo} for bot comments (regex: {args.bot_regex})...")
    print(f"Timeout: {args.timeout}s, Poll interval: {args.poll_interval}s")

    while True:
        elapsed = time.time() - start_time
        if elapsed >= args.timeout:
            result = {
                "pr_number": pr_number,
                "owner": owner,
                "repo": repo,
                "status": "timeout",
                "comments": [],
                "summary": {"total": 0, "action_required": 0, "suggestions": 0},
                "message": f"No bot comments found within {args.timeout} seconds.",
            }
            break

        attempt += 1
        print(f"[Attempt {attempt}] Elapsed: {int(elapsed)}s")

        comments = fetch_comments(gh, owner, repo, pr_number)
        if comments is None:
            print("Failed to fetch comments. Retrying...", file=sys.stderr)
            time.sleep(args.poll_interval)
            continue

        bot_comments = filter_bot_comments(comments, bot_regex)

        if len(bot_comments) >= args.require_min_comments:
            summary = classify_comments(bot_comments)
            result = {
                "pr_number": pr_number,
                "owner": owner,
                "repo": repo,
                "status": "found",
                "comments": bot_comments,
                "summary": summary,
                "message": f"Found {len(bot_comments)} bot comment(s).",
            }
            print(f"Found {len(bot_comments)} bot comment(s)!")
            break

        print(f"  Found {len(comments)} total comment(s), {len(bot_comments)} bot comment(s). Waiting...")
        time.sleep(args.poll_interval)

    # Sort comments by created_at for stable output
    result["comments"].sort(key=lambda c: c.get("created_at", ""))

    json_output = json.dumps(result, indent=2, ensure_ascii=False)

    if args.output:
        try:
            with open(args.output, "w", encoding="utf-8") as f:
                f.write(json_output)
            print(f"Results written to {args.output}")
        except OSError as e:
            print(f"Error writing output file: {e}", file=sys.stderr)
            return 2
    else:
        print(json_output)

    # Also write a human-readable summary if output path is given
    if args.output:
        summary_path = args.output.replace(".json", "_summary.txt")
        if summary_path == args.output:
            summary_path += ".summary.txt"
        try:
            with open(summary_path, "w", encoding="utf-8") as f:
                f.write(f"PR #{pr_number} Review Check\n")
                f.write(f"Status: {result['status']}\n")
                f.write(f"Total bot comments: {result['summary']['total']}\n")
                f.write(f"Action required: {result['summary']['action_required']}\n")
                f.write(f"Suggestions: {result['summary']['suggestions']}\n\n")
                for i, c in enumerate(result["comments"], 1):
                    f.write(f"--- Comment {i} ---\n")
                    f.write(f"User: {c['user']}\n")
                    f.write(f"Type: {c['type']}\n")
                    if c.get("path"):
                        f.write(f"File: {c['path']}:{c.get('line', 'N/A')}\n")
                    f.write(f"URL: {c.get('html_url', 'N/A')}\n")
                    f.write(f"Body:\n{c['body']}\n\n")
            print(f"Summary written to {summary_path}")
        except OSError:
            pass

    if result["status"] == "found":
        return 0
    else:
        return 1


if __name__ == "__main__":
    sys.exit(main())
