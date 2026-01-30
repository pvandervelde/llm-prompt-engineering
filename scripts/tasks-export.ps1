# Export tasks from Markdown to JSON format
# Converts ./.llm/tasks.md to ./.llm/tasks.json following the task-sources contract

param(
    [string]$TasksFile = ".\.llm\tasks.md",
    [string]$OutputFile = ".\.llm\tasks.json"
)

# Check if the input file exists
if (-not (Test-Path $TasksFile)) {
    Write-Error "Task file not found: $TasksFile"
    exit 1
}

# Read the Markdown file
try {
    $content = Get-Content $TasksFile -Raw
} catch {
    Write-Error "Failed to read $TasksFile : $_"
    exit 1
}

# Parse Markdown checklist and convert to JSON
$tasks = @()
$taskId = 0
$lines = $content -split "`n"

foreach ($line in $lines) {
    # Match checklist items: - [ ] or - [x]
    if ($line -match '^\s*-\s+\[([ xX])\]\s+(.+)') {
        $checked = $matches[1] -eq 'x' -or $matches[1] -eq 'X'
        $title = $matches[2].Trim()
        $taskId++
        
        $task = @{
            id       = "task-$taskId"
            title    = $title
            description = ""
            status   = if ($checked) { "completed" } else { "open" }
            checked  = $checked
        }
        
        $tasks += $task
    }
}

# Create the JSON structure
$jsonObject = @{
    tasks = $tasks
}

# Convert to JSON and write to output file
try {
    $jsonContent = $jsonObject | ConvertTo-Json -Depth 10
    Set-Content -Path $OutputFile -Value $jsonContent -Encoding UTF8
    Write-Output "Successfully exported $($tasks.Count) task(s) to $OutputFile"
    exit 0
} catch {
    Write-Error "Failed to write to $OutputFile : $_"
    exit 1
}
