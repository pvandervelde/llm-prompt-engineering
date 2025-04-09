# Tool Guidelines

All rules are to be followed in all projects. The rules are divided into categories for better organization.
Rules in this file are prefixed with `tool-` to indicate that they are tool rules.

## General

1. **tool-proactive**: Tools are not optional utilities but essential components of the thinking process.
   - Initiate appropriate tool usage without explicit human prompting
   - Treat tools as extensions of analytical capabilities
   - Multiple tools should be used in parallel when beneficial
   - In your output, mention the tools used and their purpose

2. **tool-decision-making**: When choosing tools, consider:
   - Primary goal of the current task
   - Potential for multiple tool synergy
   - Value of combined tool outputs
   - Balance between depth and response time
   - Previous tool usage patterns in the conversation
   - Query type and required verification level

## Available Tools

The following tools are available for use in this project. Use them according to the guidelines.

### General

1. Sequential Thinking is the primary entry point for all tasks. Use it liberally to guide the process.
   - Automatically begins with each new topic or request
   - Guides the selection and integration of other tools
   - Core Functions:
     - Problem decomposition
     - Tool selection strategy
     - Process monitoring
     - Course correction
     - Integration of multiple tool outputs

### Search

A number of search tools are available for use. Use them according the following
table:

| Query Type | Primary Tools | Secondary Tools | Verification |
|------------|--------------|-----------------|--------------|
| Factual | Tavily QnA + Grounding | Brave Search | Required |
| Technical | Perplexity + Tavily | Jina.ai | Optional |
| Current Events | Brave + Tavily | Perplexity | Required |
| Research | Tavily + Brave | All Others | Required |
| Source Analysis | Tavily | Grounding | Required |
| Quick Answers | Tavily QnA | Perplexity | Optional |

**Grounding** is the process of verifying and validating information from multiple sources.

- Use grounding to ensure accuracy and reliability of information
- Cross-reference findings from different tools
- Document grounding results and sources

#### Available Search Tools

1. Brave Search is the primary search tool for all queries.
   - Use for general searches and current events
   - Provides a wide range of information

2. Tavily Search is the secondary search tool for all queries.
   - Use for specific queries and to complement Brave Search
   - Provides additional context and information
   - Use for background information and contextual searches

3. Perplexity is an enhanced search tool for technical queries.
   - Use for in-depth technical searches and research
   - Provides detailed information and analysis
   - Use for complex queries requiring technical expertise
