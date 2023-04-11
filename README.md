# NAME

babyagi.pl - An AI-driven task management system

# SYNOPSIS

perl babyagi.pl

# DESCRIPTION

This Perl script implements an AI-driven task management system that
utilizes OpenAI's GPT-powered language models and Pinecone for storage
and retrieval.

The script creates, prioritizes, and executes tasks based on the given
objective and maintains a task list throughout its execution.

The script includes the following subroutines:

- add\_task - Adds a task to the task list
- get\_ada\_embedding - Retrieves an ADA embedding for the given text
- openai\_call - Calls the OpenAI API for text generation
- task\_creation\_agent - Creates new tasks based on the result of a completed task
- prioritization\_agent - Reprioritizes the task list
- execution\_agent - Executes a task based on the context
- context\_agent - Retrieves the context for a given query

# REQUIREMENTS

To run this script, you will need:

- [OpenAPI::Client::OpenAI](https://metacpan.org/pod/OpenAPI%3A%3AClient%3A%3AOpenAI)
- [OpenAPI::Client::Pinecone](https://metacpan.org/pod/OpenAPI%3A%3AClient%3A%3APinecone)

# CONFIGURATION

Before running the script, you will need to set several environment
variables, including:

- OPENAI\_API\_KEY
- OPENAI\_API\_MODEL
- PINECONE\_API\_KEY
- PINECONE\_ENVIRONMENT
- TABLE\_NAME
- OBJECTIVE
- INITIAL\_TASK (or FIRST\_TASK)

# AUTHOR

Perl version by Nelson Ferraz <nferraz@gmail.com>, based on
@yoheinakajima's [babyagi](https://github.com/yoheinakajima/babyagi/).
