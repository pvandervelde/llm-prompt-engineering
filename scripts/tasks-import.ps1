#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Import tasks from .llm/tasks.md into Beads (if available), or provide fallback guidance.

.DESCRIPTION
    Reads .llm/tasks.md, parses the Markdown checklist format, and:
    - If Beads CLI is available: converts tasks to Beads format and imports them.
    - If Beads is unavailable: outputs the parsed tasks in JSON for manual review or fallback processing.

.PARAMETER TasksFilePath
    Path to the tasks Markdown file. Defaults to './.llm/tasks.md'.

.PARAMETER BeadsCommand
    The Beads CLI command name. Defaults to 'beads'.

.EXAMPLE
    .\scripts\tasks-import.ps1
    # Attempts to import tasks from ./.llm/tasks.md into Beads.

.EXAMPLE
    .\scripts\tasks-import.ps1 -TasksFilePath './custom-tasks.md'
    # Imports from a custom tasks file.
#>

param(
    [string]$TasksFilePath = './.llm/tasks.md',
    [string]$BeadsCommand = 'beads'
)

# Helper: Check if a command is available
function Test-CommandExists
{
    param([string]$Command)
    $null = Get-Command $Command -ErrorAction SilentlyContinue
    return $?
}

# Helper: Parse Markdown checklist format
function Parse-MarkdownTasks
{
    param([string]$Content)

    $tasks = @()
    $lines = $Content -split "`n"

    foreach ($line in $lines)
    {
        # Match lines like "- [x] Task description" or "- [ ] Task description"
        if ($line -match '^\s*-\s*\[([ xX])\]\s+(.+)$')
        {
            $isCompleted = $matches[1] -eq 'x' -or $matches[1] -eq 'X'
            $description = $matches[2].Trim()

            $tasks += @{
                completed   = $isCompleted
                description = $description
            }
        }
    }

    return $tasks
}

# Helper: Convert tasks to JSON
function ConvertTo-TasksJson
{
    param([array]$Tasks)

    return @{
        version    = "1.0"
        tasks      = $Tasks
        importedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
        source     = "markdown"
    } | ConvertTo-Json -Depth 10
}

# Main logic
Write-Host "Importing tasks from $TasksFilePath..." -ForegroundColor Cyan

if (-not (Test-Path $TasksFilePath))
{
    Write-Host "Error: Tasks file not found at $TasksFilePath" -ForegroundColor Red
    exit 1
}

$content = Get-Content $TasksFilePath -Raw

if ([string]::IsNullOrWhiteSpace($content))
{
    Write-Host "Error: Tasks file is empty" -ForegroundColor Red
    exit 1
}

$parsedTasks = Parse-MarkdownTasks -Content $content

if ($parsedTasks.Count -eq 0)
{
    Write-Host "Warning: No tasks found in $TasksFilePath" -ForegroundColor Yellow
    exit 0
}

Write-Host "Parsed $($parsedTasks.Count) task(s) from Markdown." -ForegroundColor Green

# Check if Beads is available
$beadsAvailable = Test-CommandExists -Command $BeadsCommand

if ($beadsAvailable)
{
    Write-Host "Beads CLI detected. Attempting to import tasks..." -ForegroundColor Cyan

    foreach ($task in $parsedTasks)
    {
        $status = if ($task.completed)
        {
            "done" 
        }
        else
        {
            "todo" 
        }

        try
        {
            # Use Beads CLI to create/update task
            & $BeadsCommand task add --title $task.description --status $status 2>&1 | Write-Verbose
            Write-Host "  ✓ Added: $($task.description)" -ForegroundColor Green
        }
        catch
        {
            Write-Host "  ✗ Failed to add: $($task.description)" -ForegroundColor Red
            Write-Host "    Error: $_" -ForegroundColor Red
        }
    }

    Write-Host "Beads import complete." -ForegroundColor Green
}
else
{
    Write-Host "Beads CLI not available. Outputting parsed tasks in JSON format for fallback processing." -ForegroundColor Yellow
    Write-Host ""

    $jsonOutput = ConvertTo-TasksJson -Tasks $parsedTasks
    Write-Host $jsonOutput

    Write-Host ""
    Write-Host "To use Beads, install it and ensure it's in your PATH, then run this script again." -ForegroundColor Cyan
}

exit 0
