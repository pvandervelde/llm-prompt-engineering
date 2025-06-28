# Examples and Usage Guide

This guide provides practical examples of how to use the LLM Prompt Engineering tools and resources.

## Basic Usage

### Setting Up LLM Rules

1. **Install Prerequisites**

   ```powershell
   # Install the required PowerShell module
   Install-Module powershell-yaml -Force
   ```

2. **Generate Rule Files**

   ```powershell
   # From the repository root
   .\tools\generate-llm-rules.ps1
   ```

3. **Copy Generated Files to Your Project**

   ```powershell
   # For GitHub Copilot
   Copy-Item -Recurse .\output\.github\* .\.github\

   # For Cline
   Copy-Item -Recurse .\output\.clinerules\* .\

   # For Roo Coder
   Copy-Item -Recurse .\output\.roo\* .\.roo\
   ```

### Using Custom Modes

The `modes/` directory contains specialized AI assistant configurations:

#### Architect Mode

Use when planning new features or system design:

```markdown
You are now in Architect mode. I need to design a user authentication system
for a web application. Can you help me create an implementation plan?
```

The architect mode will:

- Ask clarifying questions about requirements
- Analyze technical trade-offs
- Propose multiple solution options
- Create detailed implementation plans
- Generate architectural diagrams

### Using Prompt Templates

#### Conversation Continuation

When you need to resume a complex discussion:

```markdown
I would like you to summarize the current conversation I've been having with you.
The summary should include:
* A clear overview of the main topics discussed.
* Key questions I've asked and the answers you've provided.
* Any outstanding items, open questions, or decisions that were postponed.
* Relevant assumptions or context that would help me pick up the conversation later.
```

#### Group Problem Review

For collaborative problem-solving sessions:

```markdown
We need to review this technical problem with multiple perspectives.
Can you help facilitate this by taking on different expert personas?
```

## Advanced Usage

### Customizing Rule Generation

You can customize the rule generation by modifying parameters:

```powershell
# Generate rules to custom directories
.\tools\generate-llm-rules.ps1 -outputDirCopilot "custom\.github" -outputDirCline "custom\.clinerules"

# Use different source directory
.\tools\generate-llm-rules.ps1 -sourceDir "my-custom-rules"
```

### Creating New Modes

1. **Create a new mode file**

   ```markdown
   ---
   description: Your mode description here
   tools: ['codebase', 'editFiles', 'search']
   ---

   You are an expert [YOUR SPECIALIZATION HERE]...

   Your responsibilities:
   1. First responsibility
   2. Second responsibility
   ```

2. **Test the mode**
   - Use the mode in your LLM tool
   - Verify it behaves as expected
   - Refine as needed

### Creating Custom Prompts

1. **Identify the pattern**
   - What type of interaction do you repeat often?
   - What context or formatting is usually needed?

2. **Create the template**

   ```markdown
   # Prompt Name

   Brief description of what this prompt does.

   ## Template

   I need you to [SPECIFIC TASK]...

   Please format your response as:
   1. [SECTION 1]
   2. [SECTION 2]
   ```

## Troubleshooting

### Common Issues

**PowerShell Module Not Found**

```powershell
# Solution: Install the module
Install-Module powershell-yaml -Force -AllowClobber
```

**Permission Denied Errors**

```powershell
# Solution: Run as administrator or adjust execution policy
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**Generated Files Not Working**

- Verify the output directory structure matches your LLM tool's expectations
- Check that file formats are correct for your specific tool version
- Ensure all required metadata is present

### Getting Help

1. Check the [specifications](./specs/) for technical details
2. Review existing examples in the repository
3. Open an issue for bugs or questions
4. Contribute improvements via pull requests

## Real-World Scenarios

### Scenario 1: Setting Up a New Development Project

```powershell
# 1. Generate standardized LLM rules
.\tools\generate-llm-rules.ps1

# 2. Copy to your new project
Copy-Item .\output\.github\* .\my-new-project\.github\

# 3. Start using with your preferred LLM tool
```

### Scenario 2: Collaborative Architecture Planning

1. Use the Architect mode for initial planning
2. Use group personas prompts for team review
3. Document decisions using the conversation continuation template

### Scenario 3: Maintaining Consistency Across Projects

1. Keep this repository as your central rule source
2. Regenerate rules when you update patterns
3. Deploy updated rules to all your projects

This ensures consistent LLM behavior across all your development work.
