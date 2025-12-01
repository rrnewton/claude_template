#!/usr/bin/env python3
"""
A simple wrapper to drive claude repeatedly with prompts.
"""

import argparse
import json
import os
import random
import subprocess
import sys
from pathlib import Path
from typing import List, Tuple


# Built-in prompts with weights (probabilities out of 100)
BUILTIN_PROMPTS = [
    (50, "generic_forward_progress_task.md"),  # 50% - generic forward progress
    (30, "optimization_task.md"),              # 30% - optimization
    (20, "task_gardening.md"),                 # 20% - documentation/gardening
]


def load_prompt_table(table_file: Path, script_dir: Path) -> List[Tuple[int, Path]]:
    """Load prompt table from a text file.
    
    Format:
        <NUMBER> <PROMPTFILE>
        <NUMBER> <PROMPTFILE>
        ...
    
    Where NUMBER is the weight and PROMPTFILE is the path to the prompt file.
    Paths are resolved relative to the table file's directory.
    """
    prompts = []
    table_dir = table_file.parent
    
    with open(table_file, 'r') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            # Skip empty lines and comments
            if not line or line.startswith('#'):
                continue
            
            parts = line.split(None, 1)  # Split on first whitespace
            if len(parts) != 2:
                print(f"Warning: Skipping malformed line {line_num} in {table_file}: {line}", file=sys.stderr)
                continue
            
            try:
                weight = int(parts[0])
                if weight <= 0:
                    print(f"Warning: Skipping line {line_num} in {table_file}: weight must be positive", file=sys.stderr)
                    continue
            except ValueError:
                print(f"Warning: Skipping line {line_num} in {table_file}: invalid weight '{parts[0]}'", file=sys.stderr)
                continue
            
            # Resolve prompt file path (relative to table file or absolute)
            prompt_path = Path(parts[1])
            if not prompt_path.is_absolute():
                prompt_path = table_dir / prompt_path
            
            if not prompt_path.exists():
                print(f"Warning: Skipping line {line_num} in {table_file}: file not found '{prompt_path}'", file=sys.stderr)
                continue
            
            prompts.append((weight, prompt_path))
    
    if not prompts:
        raise ValueError(f"No valid prompts found in {table_file}")
    
    return prompts


def select_weighted_prompt(prompts: List[Tuple[int, Path]]) -> Path:
    """Select a random prompt based on weights."""
    total_weight = sum(weight for weight, _ in prompts)
    rand = random.randint(1, total_weight)

    cumulative = 0
    for weight, path in prompts:
        cumulative += weight
        if rand <= cumulative:
            return path

    # Fallback (shouldn't reach here)
    return prompts[0][1]


def find_next_log_number(logs_dir: Path) -> int:
    """Find the next available log number."""
    num = 1
    while (logs_dir / f"claude_workstream{num:02d}.jsonl").exists():
        num += 1
    return num


def get_working_directory() -> Path:
    """Get the working directory for running claude.

    Uses git repo root if available, otherwise current working directory.
    """
    try:
        result = subprocess.run(
            ['git', 'rev-parse', '--show-toplevel'],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            return Path(result.stdout.strip())
    except Exception:
        pass
    return Path.cwd()


CHECK_COMPLETE_PROMPT = """Look at the history of this conversation above. Is the prior task complete? If it seems like it's at a reasonable stopping point, respond with an answer beginning with "Yes.". This means that we have wrapped up a logical task, left the project in a sensible state, and are ready to begin work on something new. You may check the current working copy status to make sure the changes are committed as well, or look at the contents of recent commits.

If the task not complete for any reason (for example, one milestone completed but remaining work identified), respond beginning with "No.". After the yes/no answer you can briefly provide your reasoning."""


CONTINUE_TASK_PROMPT_TEMPLATE = """Please continue work on the prior task. As a reminder, here was the request that kicked off that work:
---------
{prior_prompt}"""


def check_task_complete(work_dir: Path) -> bool:
    """Ask Claude if the prior task is complete by continuing the conversation.

    Returns True if task is complete (response starts with "Yes"), False otherwise.
    """
    cmd = [
        'claude',
        '--continue',
        '-p', CHECK_COMPLETE_PROMPT
    ]

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            cwd=work_dir,
            timeout=120
        )

        response = result.stdout.strip()
        print(f"\n=== Task completion check ===")
        print(f"Claude's response: {response[:500]}{'...' if len(response) > 500 else ''}")

        # Check if response starts with "Yes" (case insensitive)
        is_complete = response.lower().startswith("yes")
        print(f"Task complete: {is_complete}\n")
        return is_complete

    except subprocess.TimeoutExpired:
        print("Warning: Task completion check timed out, assuming incomplete", file=sys.stderr)
        return False
    except Exception as e:
        print(f"Warning: Failed to check task completion: {e}, assuming incomplete", file=sys.stderr)
        return False


def run_iteration(iteration: int, total: int, prompt_file: Path, logs_dir: Path, use_happy: bool, script_dir: Path,
                  work_dir: Path, continue_conversation: bool = False, override_prompt: str = None) -> bool:
    """Run a single iteration with claude.

    Args:
        iteration: Current iteration number
        total: Total number of iterations
        prompt_file: Path to the prompt file to use
        logs_dir: Directory for log files
        use_happy: Whether to use happy wrapper
        script_dir: Path to the script directory
        work_dir: Working directory for running claude
        continue_conversation: If True, use --continue flag to continue prior conversation
        override_prompt: If provided, use this string as the prompt instead of reading from prompt_file
    """
    print(f"\n=== Iteration {iteration} of {total} ===")

    # Find unused log filename
    log_num = find_next_log_number(logs_dir)
    log_file = logs_dir / f"claude_workstream{log_num:02d}.jsonl"
    latest_link = logs_dir / "claude_workstream_latest.jsonl"

    print(f"Using log file: {log_file}")

    # Update latest symlink
    if latest_link.exists() or latest_link.is_symlink():
        latest_link.unlink()
    latest_link.symlink_to(log_file.name)

    # Determine which prompt to use and log it
    if override_prompt:
        print(f"Using continuation prompt (based on: {prompt_file.name})")
        prompt_content = override_prompt
    else:
        print(f"Using prompt: {prompt_file.name}")
        # Read prompt content (use absolute path which works regardless of CWD)
        with open(prompt_file, 'r') as f:
            prompt_content = f.read()

    # Determine conversation continuation flag
    # --continue: continue the most recent conversation
    # -c: allow multiple conversations in one session (but start fresh)
    continuation_flag = '--continue' if continue_conversation else '-c'

    # Build claude command
    if use_happy:
        # Use happy wrapper
        cmd = [
            'happy',
            'claude',
            '--dangerously-skip-permissions',
            '--verbose',
            '--output-format', 'stream-json',
            continuation_flag,
            '-p', prompt_content
        ]
    else:
        # Direct claude command
        cmd = [
            'claude',
            '--dangerously-skip-permissions',
            '--verbose',
            '--output-format', 'stream-json',
            continuation_flag,
            '-p', prompt_content
        ]

    # Run claude command with tee-like behavior
    try:
        with open(log_file, 'a') as log:
            # Run subprocess in working directory
            process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                cwd=work_dir
            )

            # Process output line by line
            for line in process.stdout:
                # Write to log file
                log.write(line)
                log.flush()

                # Try to parse and display
                try:
                    data = json.loads(line)
                    if data.get('type') in ['assistant', 'result']:
                        # Extract text content
                        if 'message' in data and 'content' in data['message']:
                            for content in data['message']['content']:
                                if 'text' in content:
                                    print(content['text'], end='')
                        elif 'result' in data:
                            print(f"\nResult: {data['result']}")
                except json.JSONDecodeError:
                    pass  # Skip malformed JSON

            process.wait()

            if process.returncode != 0:
                stderr = process.stderr.read()
                print(f"Error running claude: {stderr}", file=sys.stderr)
                return False

    except Exception as e:
        print(f"Error during iteration: {e}", file=sys.stderr)
        return False

    # Check for error.txt in working directory
    error_file = work_dir / 'error.txt'
    if error_file.exists():
        print("\nError detected in error.txt:")
        print(error_file.read_text())
        return False

    print(f"\nCompleted iteration {iteration}")
    return True


def main():
    # Save original working directory
    original_cwd = Path.cwd()

    parser = argparse.ArgumentParser(
        description='Drive claude repeatedly with prompts',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Built-in prompt types for --constant-builtin:
  optimize  - optimization_task.md
  general   - generic_forward_progress_task.md
  tasks     - task_gardening.md

Random builtin weights:
  - generic_forward_progress_task.md (50%% probability)
  - optimization_task.md             (30%% probability)
  - task_gardening.md                (20%% probability)

Examples:
  %(prog)s --random-builtin 5                    # Random selection from built-ins
  %(prog)s --constant-builtin=optimize 5         # All iterations use optimization_task.md
  %(prog)s --constant-builtin=general 5          # All iterations use generic_forward_progress_task.md
  %(prog)s --constant-prompt task.md 5           # All iterations use custom prompt file
  %(prog)s --prompt-table table.txt 5            # Use weighted prompts from table file
  %(prog)s --random-builtin --happy 5            # Use happy wrapper with session title
  %(prog)s --random-builtin --continue-unfinished 5  # Check task completion between iterations

Prompt table format (for --prompt-table):
  Each line: <WEIGHT> <PROMPTFILE>
  Example table.txt:
    10 prompts/generic_forward_progress_task.md
    10 prompts/optimization_task.md
  Weights are relative (10 10 = 50%% each, same as 1 1 or 100 100)
        """
    )

    parser.add_argument('iterations', type=int, help='Number of iterations to run')

    # Prompt Supply Stream options (mutually exclusive, one required)
    prompt_stream_group = parser.add_argument_group('Prompt Supply Stream (one required)')
    prompt_stream = prompt_stream_group.add_mutually_exclusive_group()
    prompt_stream.add_argument('--random-builtin', action='store_true',
                               help='Randomly select from built-in prompts each iteration')
    prompt_stream.add_argument('--constant-builtin', type=str, metavar='TYPE',
                               choices=['optimize', 'general', 'tasks'],
                               help='Use a built-in prompt for all iterations (optimize|general|tasks)')
    prompt_stream.add_argument('--constant-prompt', type=str, metavar='PROMPT_FILE',
                               help='Use specified prompt file for all iterations')
    prompt_stream.add_argument('--prompt-table', type=str, metavar='TABLE_FILE',
                               help='Load weighted prompt table from file')

    # Additional options
    options_group = parser.add_argument_group('Additional Options')
    options_group.add_argument('--happy', action='store_true',
                               help='Use happy wrapper (reads session title from .session_title.txt)')
    options_group.add_argument('--continue-unfinished', action='store_true',
                               help='Check if prior task is complete before starting new prompt')

    args = parser.parse_args()

    # Require exactly one prompt supply stream option
    prompt_stream_options = [args.random_builtin, args.constant_builtin, args.constant_prompt, args.prompt_table]
    if not any(prompt_stream_options):
        parser.error("One of --random-builtin, --constant-builtin, --constant-prompt, or --prompt-table is required")

    # Setup paths
    script_dir = Path(__file__).parent
    work_dir = get_working_directory()
    print(f"Working directory: {work_dir}")
    prompt_dir = script_dir / 'prompts'
    logs_dir = script_dir / 'logs'

    # Ensure logs directory exists
    logs_dir.mkdir(exist_ok=True)

    # Build list of built-in prompts with absolute paths
    builtin_prompts = [
        (weight, prompt_dir / filename)
        for weight, filename in BUILTIN_PROMPTS
    ]

    # Determine prompt supply stream mode
    if args.prompt_table:
        # Load prompts from table file (resolve relative to original CWD)
        table_path = Path(args.prompt_table)
        if not table_path.is_absolute():
            table_path = original_cwd / table_path
        table_path = table_path.resolve()
        if not table_path.exists():
            parser.error(f"Prompt table file not found: {table_path}")
        try:
            builtin_prompts = load_prompt_table(table_path, script_dir)
            prompt_mode = f"weighted table ({table_path.name})"
            print(f"Loaded {len(builtin_prompts)} prompts from {table_path}")
            total_weight = sum(w for w, _ in builtin_prompts)
            for weight, path in builtin_prompts:
                probability = (weight / total_weight) * 100
                print(f"  {weight:3d} ({probability:5.1f}%) {path.name}")
            print()
        except Exception as e:
            parser.error(f"Failed to load prompt table: {e}")
        fixed_prompt = None
        use_constant_mode = False
    elif args.constant_prompt:
        # Resolve --constant-prompt path relative to original CWD
        prompt_path = Path(args.constant_prompt)
        if not prompt_path.is_absolute():
            prompt_path = original_cwd / prompt_path
        prompt_path = prompt_path.resolve()
        if not prompt_path.exists():
            parser.error(f"Prompt file not found: {prompt_path}")
        fixed_prompt = prompt_path
        prompt_mode = f"constant prompt ({prompt_path.name})"
        use_constant_mode = True
    elif args.constant_builtin:
        builtin_map = {
            'optimize': ("optimization_task.md", "optimization"),
            'general': ("generic_forward_progress_task.md", "general forward progress"),
            'tasks': ("task_gardening.md", "task gardening"),
        }
        filename, prompt_mode = builtin_map[args.constant_builtin]
        fixed_prompt = prompt_dir / filename
        use_constant_mode = True
    elif args.random_builtin:
        fixed_prompt = None
        prompt_mode = "random weighted selection"
        use_constant_mode = False
    else:
        # Should not reach here due to earlier validation
        parser.error("No prompt supply stream specified")

    # Print mode message
    print(f"Prompt mode: {prompt_mode}\n")

    if args.continue_unfinished:
        print("Continue-unfinished mode enabled: will check if prior task is complete before each iteration\n")

    # Track the prior prompt content for continuation
    prior_prompt_content = None

    # Run iterations
    for i in range(1, args.iterations + 1):
        # Check if we should continue a prior task instead of starting a new one
        continue_prior_task = False
        if args.continue_unfinished and prior_prompt_content is not None:
            print(f"\n--- Checking if prior task is complete before iteration {i} ---")
            task_complete = check_task_complete(work_dir)
            if not task_complete:
                continue_prior_task = True
                print(f"Prior task incomplete - continuing previous work instead of starting iteration {i}")

        if continue_prior_task:
            # Continue working on the prior task
            # We still need a prompt_file for logging purposes, use the last one
            continuation_prompt = CONTINUE_TASK_PROMPT_TEMPLATE.format(prior_prompt=prior_prompt_content)
            success = run_iteration(i, args.iterations, prompt_file, logs_dir, args.happy, script_dir,
                                    work_dir, continue_conversation=True, override_prompt=continuation_prompt)
            # Note: prior_prompt_content stays the same since we're continuing the same task
        else:
            # Select a new prompt for this iteration
            if use_constant_mode:
                # Constant mode: use the same prompt for all iterations
                prompt_file = fixed_prompt
                print(f"Using {prompt_mode} for iteration {i}")
            else:
                # Random/table mode: select from prompts based on weights
                prompt_file = select_weighted_prompt(builtin_prompts)
                print(f"Selected prompt for iteration {i}: {prompt_file.name}")

            # Read and store the prompt content for potential future continuation
            with open(prompt_file, 'r') as f:
                prior_prompt_content = f.read()

            # Run the iteration with a fresh prompt
            success = run_iteration(i, args.iterations, prompt_file, logs_dir, args.happy, script_dir, work_dir)

        if not success:
            sys.exit(1)

    print(f"\nSuccessfully completed all {args.iterations} iterations")
    sys.exit(0)


if __name__ == '__main__':
    main()
