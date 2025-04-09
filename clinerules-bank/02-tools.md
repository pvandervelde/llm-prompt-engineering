# Tool Guidelines

All rules are to be followed in all projects. The rules are divided into categories for better organization.
Rules in this file are prefixed with `tool-` to indicate that they are tool rules.

## General

1. **tool-proactive**: Tools are not optional utilities but essential components of the thinking process.
   - Initiate appropriate tool usage without explicit human prompting
   - Treat tools as extensions of analytical capabilities
   - Multiple tools should be used in parallel when beneficial

2. **tool-decision-making**: When choosing tools, consider:
   - Primary goal of the current task
   - Potential for multiple tool synergy
   - Value of combined tool outputs
   - Balance between depth and response time
   - Previous tool usage patterns in the conversation
   - Query type and required verification level

3. **tool-grounding**: Grounding is the process of verifying and validating information from multiple sources.
   - Use grounding to ensure accuracy and reliability of information
   - Cross-reference findings from different tools
   - Document grounding results and sources

## Hierarchy

1. **tool-hierarchy-sequential-thinking**: Sequential Thinking is the primary entry point for all tasks.
   - Automatically begins with each new topic or request
   - Guides the selection and integration of other tools
   - Core Functions:
     - Problem decomposition
     - Tool selection strategy
     - Process monitoring
     - Course correction
     - Integration of multiple tool outputs

2. **tool-information-search**: All search tools must be used according to the query type matrix for
   comprehensive coverage.
   1. primary search tool for all searches: Brave search
   2. secondary search tool for all searches: Tavily search
   3. enhanced search tools for specific query types: Perplexity for technical queries and Tavily
      context for background information

## Query Type Matrix

| Query Type | Primary Tools | Secondary Tools | Verification |
|------------|--------------|-----------------|--------------|
| Factual | Tavily QnA + Grounding | Brave Search | Required |
| Technical | Perplexity + Tavily | Jina.ai | Optional |
| Current Events | Brave + Tavily | Perplexity | Required |
| Research | Tavily + Brave | All Others | Required |
| Source Analysis | Jina.ai + Tavily | Grounding | Required |
| Quick Answers | Tavily QnA | Perplexity | Optional |
