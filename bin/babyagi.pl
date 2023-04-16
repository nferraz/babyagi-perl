#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long;
use Time::HiRes qw( sleep );

use BabyAGI;

our $VERSION = '0.01';

my %options;

GetOptions( \%options, "openai-api-key=s", "openai-api-model=s", "pinecone-api-key=s", "pinecone-environment=s",
    "table-name=s", "objective=s", "initial-task=s", )
    or die("Error in command line arguments\n");

my $babyagi = BabyAGI->new(
    OPENAI_API_KEY       => $options{'openai-api-key'},
    OPENAI_API_MODEL     => $options{'openai-api-model'},
    PINECONE_API_KEY     => $options{'pinecone-api-key'},
    PINECONE_ENVIRONMENT => $options{'pinecone-environment'},
    TABLE_NAME           => $options{'table-name'},
    OBJECTIVE            => $options{'objective'},
    INITIAL_TASK         => $options{'initial-task'},
);

# Task list
my @task_list;

sub task_creation_agent {
    my ( $objective, $result, $task_description, @task_list ) = @_;
    my $task_list_str = join( ', ', @task_list );
    my $prompt        = <<"EOF";
You are a task creation AI that uses the result of an execution agent to create new tasks with the following objective: $objective,
The last completed task has the result: $result.
This result was based on this task description: $task_description. These are incomplete tasks: $task_list_str.
Based on the result, create new tasks to be completed by the AI system that do not overlap with incomplete tasks.
Return the tasks as an array.
EOF
    my $response  = $babyagi->generate_ideas( prompt => $prompt );
    my @new_tasks = split( "\n", $response );
    return map { { task_name => $_ } } @new_tasks;
}

sub prioritization_agent {
    my ($this_task_id) = @_;
    my @task_names     = map { $_->{task_name} } @task_list;
    my $next_task_id   = $this_task_id + 1;
    my $prompt         = <<"EOF";
You are a task prioritization AI tasked with cleaning the formatting of and reprioritizing the following tasks: @task_names.
Consider the ultimate objective of your team: $babyagi->{OBJECTIVE}.
Do not remove any tasks. Return the result as a numbered list, like:
#. First task
#. Second task
Start the task list with number $next_task_id.
EOF
    my $response  = $babyagi->generate_ideas( prompt => $prompt );
    my @new_tasks = split( "\n", $response );
    @task_list = ();
    foreach my $task_string (@new_tasks) {
        my ( $task_id, $task_name ) = $task_string =~ /^\s*(\d+)\.\s*(.+)\s*$/;
        push @task_list, { task_id => $task_id, task_name => $task_name } if $task_id && $task_name;
    }
}

sub execution_agent {
    my ( $objective, $task ) = @_;
    my $context = join( "\n", context_agent( query => $objective, n => 5 ) );
    my $prompt  = <<"EOF";
You are an AI who performs one task based on the following objective: $objective\n.
Take into account these previously completed tasks: $context\n.
Your task: $task\nResponse:
EOF
    return $babyagi->generate_ideas( prompt => $prompt, temperature => 0.7, max_tokens => 2000 );
}

sub context_agent {
    my (%args) = @_;

    my $response_data = $babyagi->recall(
        query => $args{query},
        n     => $args{n} || 5,
    );

    my @sorted_results = sort { $b->{score} <=> $a->{score} } @{ $response_data->{matches} };
    return map { $_->{metadata}->{task} } @sorted_results;
}

# Add the first task
my $first_task = { task_id => 1, task_name => $babyagi->{INITIAL_TASK} };
push @task_list, $first_task;

# Main loop
my $task_id_counter = 1;
while (1) {
    if (@task_list) {
        # Print the task list
        print("\n*****TASK LIST*****\n");
        foreach my $t (@task_list) {
            print("$t->{task_id}: $t->{task_name}\n");
        }

        # Step 1: Pull the first task
        my $task = shift @task_list;
        print("\n*****NEXT TASK*****\n");
        print("$task->{task_id}: $task->{task_name}\n");

        # Send to execution function to complete the task based on the context
        my $result       = execution_agent( $babyagi->{OBJECTIVE}, $task->{task_name} );
        my $this_task_id = int( $task->{task_id} );
        print("\n*****TASK RESULT*****\n");
        print("$result\n\n\n");

        # Step 2: Enrich result and store in Pinecone
        my $enriched_result = $babyagi->memorize(
            task   => $task,
            result => $result,
        );

        # Step 3: Create new tasks and reprioritize task list
        my @new_tasks =
            task_creation_agent( $babyagi->{OBJECTIVE}, $enriched_result, $task->{task_name},
            map { $_->{task_name} } @task_list );
        foreach my $new_task (@new_tasks) {
            $task_id_counter += 1;
            $new_task->{task_id} = $task_id_counter;
            push @task_list, $new_task;
        }
        prioritization_agent($this_task_id);
    }
    sleep 1;    # Sleep before checking the task list again
}

__END__

=head1 NAME

babyagi.pl - An AI-driven task management system

=head1 SYNOPSIS

perl babyagi.pl

=head1 DESCRIPTION

This Perl script implements an AI-driven task management system that
utilizes OpenAI's GPT-powered language models and Pinecone for storage
and retrieval.

The script creates, prioritizes, and executes tasks based on the given
objective and maintains a task list throughout its execution.

The script includes the following subroutines:

=over

=item * task_creation_agent - Creates new tasks based on the result of a completed task

=item * prioritization_agent - Reprioritizes the task list

=item * execution_agent - Executes a task based on the context

=item * context_agent - Retrieves the context for a given query

=back

=head1 REQUIREMENTS

To run this script, you will need:

=over

=item * L<OpenAPI::Client::OpenAI>

=item * L<OpenAPI::Client::Pinecone>

=back

=head1 CONFIGURATION

Before running the script, you will need to set several environment
variables, including:

=over

=item * OPENAI_API_KEY

=item * OPENAI_API_MODEL

=item * PINECONE_API_KEY

=item * PINECONE_ENVIRONMENT

=item * TABLE_NAME

=item * OBJECTIVE

=item * INITIAL_TASK (or FIRST_TASK)

=back

=head1 AUTHOR

Perl version by Nelson Ferraz E<lt>nferraz@gmail.comE<gt>, based on
@yoheinakajima's L<babyagi|https://github.com/yoheinakajima/babyagi/>.
