#!/usr/bin/env python3
"""
Generate natural, human-sounding Jira comments for commits.
This script uses AI to create comments that feel like a developer wrote them,
rather than formal AI-generated documentation.
"""

import os
import sys
import json
import subprocess
import argparse
from datetime import datetime
from typing import Optional, Dict, Any

# Color codes for terminal output
BLUE = '\033[94m'
GREEN = '\033[92m'
YELLOW = '\033[93m'
RED = '\033[91m'
NC = '\033[0m'  # No Color


def print_color(message: str, color: str = NC):
    """Print colored message to stderr"""
    print(f"{color}{message}{NC}", file=sys.stderr)


def get_openai_api_key() -> Optional[str]:
    """Get OpenAI API key from environment or keychain"""
    api_key = os.environ.get('OPENAI_API_KEY')
    if api_key:
        return api_key
    
    # Try to get from keychain on macOS
    try:
        result = subprocess.run(
            ['security', 'find-generic-password', '-w', '-s', 'openai-api-key', '-a', 'automation'],
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError:
        return None


def get_anthropic_api_key() -> Optional[str]:
    """Get Anthropic API key from environment or keychain"""
    api_key = os.environ.get('ANTHROPIC_API_KEY')
    if api_key:
        return api_key
    
    # Try to get from keychain on macOS
    try:
        result = subprocess.run(
            ['security', 'find-generic-password', '-w', '-s', 'anthropic-api-key', '-a', 'automation'],
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError:
        return None


def generate_with_openai(prompt: str, api_key: str) -> Optional[str]:
    """Generate comment using OpenAI API"""
    import requests
    
    try:
        response = requests.post(
            'https://api.openai.com/v1/chat/completions',
            headers={
                'Authorization': f'Bearer {api_key}',
                'Content-Type': 'application/json'
            },
            json={
                'model': 'gpt-4-turbo-preview',
                'messages': [
                    {
                        'role': 'system',
                        'content': 'You are a helpful senior developer writing informal updates to your team. Write naturally and conversationally, like you\'re explaining what you did to a colleague. Output ONLY the comment text itself - no meta-commentary or explanations about what you\'re writing.'
                    },
                    {
                        'role': 'user',
                        'content': prompt
                    }
                ],
                'temperature': 0.7,
                'max_tokens': 2000
            },
            timeout=60
        )
        
        if response.status_code == 200:
            data = response.json()
            return data['choices'][0]['message']['content'].strip()
        else:
            print_color(f"❌ OpenAI API error: {response.status_code}", RED)
            return None
            
    except Exception as e:
        print_color(f"❌ OpenAI error: {str(e)}", RED)
        return None


def generate_with_claude(prompt: str, api_key: str) -> Optional[str]:
    """Generate comment using Anthropic Claude API"""
    import requests
    
    try:
        response = requests.post(
            'https://api.anthropic.com/v1/messages',
            headers={
                'x-api-key': api_key,
                'anthropic-version': '2023-06-01',
                'content-type': 'application/json'
            },
            json={
                'model': 'claude-3-5-sonnet-20241022',
                'max_tokens': 2000,
                'temperature': 0.7,
                'system': 'You are a helpful senior developer writing informal updates to your team. Write naturally and conversationally, like you\'re explaining what you did to a colleague. Output ONLY the comment text itself - no meta-commentary or explanations about what you\'re writing.',
                'messages': [
                    {
                        'role': 'user',
                        'content': prompt
                    }
                ]
            },
            timeout=60
        )
        
        if response.status_code == 200:
            data = response.json()
            return data['content'][0]['text'].strip()
        else:
            print_color(f"❌ Claude API error: {response.status_code}", RED)
            return None
            
    except Exception as e:
        print_color(f"❌ Claude error: {str(e)}", RED)
        return None


def generate_with_cursor(prompt: str) -> Optional[str]:
    """Generate comment using Cursor Agent CLI"""
    try:
        # Check if cursor-agent is available
        result = subprocess.run(['which', 'cursor-agent'], capture_output=True, text=True)
        if result.returncode != 0:
            # Try common installation paths
            cursor_paths = [
                os.path.expanduser('~/.local/bin/cursor-agent'),
                os.path.expanduser('~/.cursor/bin/cursor-agent'),
                '/usr/local/bin/cursor-agent'
            ]
            cursor_agent = None
            for path in cursor_paths:
                if os.path.isfile(path) and os.access(path, os.X_OK):
                    cursor_agent = path
                    break
            
            if not cursor_agent:
                print_color("❌ cursor-agent not found", RED)
                return None
        else:
            cursor_agent = 'cursor-agent'
        
        # Run cursor-agent with prompt via stdin
        result = subprocess.run(
            [cursor_agent, 'chat'],
            input=prompt,
            capture_output=True,
            text=True,
            timeout=60
        )
        
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
        else:
            error_msg = result.stderr.strip() if result.stderr else "Unknown error"
            print_color(f"❌ Cursor Agent error: {error_msg}", RED)
            return None
                
    except subprocess.TimeoutExpired:
        print_color("❌ Cursor Agent timeout", RED)
        return None
    except Exception as e:
        print_color(f"❌ Cursor Agent error: {str(e)}", RED)
        return None


def build_natural_prompt(commit_info: Dict[str, Any]) -> str:
    """
    Build a prompt that generates natural, developer-written comments.
    
    The goal is to make the AI write like a real developer updating their team,
    not like formal documentation.
    """
    
    commit_msg = commit_info.get('message', '')
    commit_sha = commit_info.get('sha', '')
    branch = commit_info.get('branch', '')
    author = commit_info.get('author', '')
    commit_date = commit_info.get('date', '')
    commit_url = commit_info.get('url', '')
    diff_summary = commit_info.get('diff_summary', '')
    ticket_details = commit_info.get('ticket_details', '')
    files_changed = commit_info.get('files_changed', 0)
    
    # Build the prompt
    prompt = f"""CRITICAL INSTRUCTION: Output ONLY the Jira comment text itself. Do NOT include any meta-commentary, explanations, or descriptions about what you're writing. Your output will be posted directly to Jira.

Write an informal Jira comment update from a developer who just completed a task. Write it like you're explaining what you did to your team lead or project manager - casual, conversational, but still professional.

CONTEXT:
- Commit: {commit_msg}
- SHA: {commit_sha}
- Branch: {branch}
- Files changed: {files_changed}
- Commit link: {commit_url}
{"- Ticket context: " + ticket_details if ticket_details else ""}

CODE CHANGES:
{diff_summary}

IMPORTANT STYLE GUIDELINES:
1. Write in FIRST PERSON ("I completed", "I fixed", "I updated") - like a developer writing their own update
2. Be CASUAL and CONVERSATIONAL - use contractions, natural language, avoid formal structure
3. Sound HUMAN - vary your sentence structure, use natural transitions
4. Be BRIEF but informative - don't over-explain
5. Use simple markdown (**, -, bullets) - NO fancy formatting
6. Include practical details that matter for testing
7. DON'T use section headers like "Summary:", "Issue:", etc. - just write naturally
8. Start with a brief statement like "Hey team, I've completed the [task name]" or "Done with [task]" or similar

REQUIRED CONTENT (but write it naturally, not as sections):
1. Brief intro saying you completed the task
2. What the issue/requirement was (in plain terms)
3. What you fixed/changed (technical but in layman terms - explain WHAT you did, not just HOW)
4. Link to commit
5. How to test it (practical steps)
6. Any additional notes (edge cases, things to watch, etc.)

EXAMPLE TONE (adapt to the actual commit):
"Hey team, just finished up the user authentication task.

The issue was that users were getting logged out randomly when switching between tabs. Turned out the session token wasn't being refreshed properly.

Here's what I fixed:
- Updated the token refresh logic to check expiry every 5 minutes instead of just on page load
- Added a background service that keeps the session alive as long as the user is active
- Fixed a race condition where multiple tabs could trigger conflicting refresh requests

Commit: {commit_url}

To test this:
1. Log in to the app
2. Open it in multiple tabs
3. Leave it idle for 10-15 minutes, then try to do something (like click on a button)
4. You should stay logged in and everything should work normally
5. Also try switching between tabs rapidly - no weird logout behavior

Watch out for:
- The background service runs every 5 mins, so it might take a bit to see the effect
- If you're testing with a dev account, make sure the token expiry is set to something reasonable (not 1 year!)

Let me know if you see any issues!"

REMEMBER: Output ONLY the comment text. Start directly with something like "Hey team" or "Done with". Do NOT write things like "Here's the comment:" or "The comment is ready" or any other meta-text. Your output will be posted directly to Jira."""

    return prompt


def clean_ai_response(text: str) -> str:
    """
    Clean up AI response by removing meta-commentary.
    Sometimes AIs add explanatory text instead of just outputting the comment.
    """
    if not text:
        return text
    
    # List of meta-commentary patterns to detect
    meta_patterns = [
        "here's the comment",
        "here is the comment",
        "the comment is",
        "i've generated",
        "i've created",
        "i've written",
        "generated comment",
        "here's what i",
        "let me write",
    ]
    
    # Check if the response starts with meta-commentary
    lower_text = text.lower()
    for pattern in meta_patterns:
        if lower_text.startswith(pattern):
            # This is likely meta-commentary, not the actual comment
            print_color("⚠️  Detected meta-commentary in AI response, attempting to clean...", YELLOW)
            # Try to find where the actual comment starts
            lines = text.split('\n')
            # Skip lines that look like meta-commentary
            actual_comment_lines = []
            found_start = False
            for line in lines:
                line_lower = line.lower().strip()
                if not found_start:
                    # Look for typical comment starts
                    if any(start in line_lower for start in ['hey team', 'hi team', 'done with', 'just finished', 'completed']):
                        found_start = True
                        actual_comment_lines.append(line)
                else:
                    actual_comment_lines.append(line)
            
            if actual_comment_lines:
                return '\n'.join(actual_comment_lines)
            
            # If we couldn't find a clear start, return original
            print_color("⚠️  Could not identify actual comment, using original response", YELLOW)
            return text
    
    return text


def generate_comment(commit_info: Dict[str, Any]) -> Optional[str]:
    """Generate a natural Jira comment using available AI providers"""
    
    prompt = build_natural_prompt(commit_info)
    
    # Try OpenAI first
    openai_key = get_openai_api_key()
    if openai_key:
        print_color("🤖 Generating natural comment with OpenAI...", BLUE)
        comment = generate_with_openai(prompt, openai_key)
        if comment:
            return clean_ai_response(comment)
    
    # Try Claude
    claude_key = get_anthropic_api_key()
    if claude_key:
        print_color("🤖 Generating natural comment with Claude...", BLUE)
        comment = generate_with_claude(prompt, claude_key)
        if comment:
            return clean_ai_response(comment)
    
    # Try Cursor Agent
    print_color("🎨 Trying Cursor Agent...", BLUE)
    comment = generate_with_cursor(prompt)
    if comment:
        return clean_ai_response(comment)
    
    print_color("❌ No AI provider available or all failed", RED)
    print_color("💡 Options:", YELLOW)
    print_color("   - Set OPENAI_API_KEY environment variable", YELLOW)
    print_color("   - Set ANTHROPIC_API_KEY environment variable", YELLOW)
    print_color("   - Install and authenticate cursor-agent", YELLOW)
    return None


def main():
    parser = argparse.ArgumentParser(
        description='Generate natural, human-sounding Jira comments for commits'
    )
    parser.add_argument('--commit-sha', required=True, help='Git commit SHA')
    parser.add_argument('--commit-message', required=True, help='Commit message')
    parser.add_argument('--branch', required=True, help='Git branch name')
    parser.add_argument('--author', required=True, help='Commit author')
    parser.add_argument('--date', required=True, help='Commit date')
    parser.add_argument('--commit-url', default='', help='URL to commit')
    parser.add_argument('--diff-summary', default='', help='Summary of changes')
    parser.add_argument('--files-changed', type=int, default=0, help='Number of files changed')
    parser.add_argument('--ticket-details', default='', help='Jira ticket details')
    parser.add_argument('--json-input', help='Path to JSON file with all commit info')
    
    args = parser.parse_args()
    
    # Build commit info dict
    if args.json_input:
        # Read from JSON file
        try:
            with open(args.json_input, 'r') as f:
                commit_info = json.load(f)
        except Exception as e:
            print_color(f"❌ Failed to read JSON input: {str(e)}", RED)
            sys.exit(1)
    else:
        # Use command line arguments
        commit_info = {
            'sha': args.commit_sha,
            'message': args.commit_message,
            'branch': args.branch,
            'author': args.author,
            'date': args.date,
            'url': args.commit_url,
            'diff_summary': args.diff_summary,
            'files_changed': args.files_changed,
            'ticket_details': args.ticket_details
        }
    
    # Generate comment
    comment = generate_comment(commit_info)
    
    if comment:
        # Output the comment to stdout
        print(comment)
        sys.exit(0)
    else:
        print_color("❌ Failed to generate comment", RED)
        sys.exit(1)


if __name__ == '__main__':
    main()
