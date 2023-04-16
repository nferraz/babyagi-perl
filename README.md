# NAME

babyagi.pl - An AI-driven task management system

# SYNOPSIS

    perl babyagi_script.pl [options]

Options:

    --api-key=<openai_api_key>         Your OpenAI API key
    --model=<openai_api_model>         OpenAI API model, e.g., 'gpt-3.5-turbo'
    --pinecone-key=<pinecone_api_key>  Your Pinecone API key
    --pinecone-env=<pinecone_env>      Pinecone environment
    --table-name=<table_name>          Pinecone table name
    --objective=<objective>            Objective of the BabyAGI instance
    --initial-task=<initial_task>      Initial task to start with

# DESCRIPTION

This script is a command-line interface for the BabyAGI Perl module. It
demonstrates how to use the BabyAGI module to manage, prioritize, and
execute tasks using OpenAI and Pinecone.

The script includes the following subroutines:

- task\_creation\_agent - Creates new tasks based on the result of a completed task
- prioritization\_agent - Reprioritizes the task list
- execution\_agent - Executes a task based on the context
- context\_agent - Retrieves the context for a given query

# CONFIGURATION

Before running the script, it's recommended to set the following
environment variables:

- OPENAI\_API\_KEY
- OPENAI\_API\_MODEL
- PINECONE\_API\_KEY
- PINECONE\_ENVIRONMENT
- TABLE\_NAME
- OBJECTIVE
- INITIAL\_TASK (or FIRST\_TASK)

# AUTHOR

Perl version by Nelson Ferraz <nferraz@gmail.com>,
based on [@yoheinakajima](https://twitter.com/yoheinakajima)'s
[babyagi](https://github.com/yoheinakajima/babyagi/).
