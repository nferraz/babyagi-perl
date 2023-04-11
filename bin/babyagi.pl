#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long;
use Time::HiRes qw( sleep );

use Dotenv;
use OpenAPI::Client::OpenAI;
use OpenAPI::Client::Pinecone;

our $VERSION = '0.01';

# Load environment variables from .env file
Dotenv->load();

my $OPENAI_API_KEY       = $ENV{"OPENAI_API_KEY"}       || "";
my $OPENAI_API_MODEL     = $ENV{"OPENAI_API_MODEL"}     || "gpt-3.5-turbo";
my $PINECONE_API_KEY     = $ENV{"PINECONE_API_KEY"}     || "";
my $PINECONE_ENVIRONMENT = $ENV{"PINECONE_ENVIRONMENT"} || "";
my $TABLE_NAME           = $ENV{"TABLE_NAME"}           || "";
my $OBJECTIVE            = $ENV{"OBJECTIVE"}            || "";
my $INITIAL_TASK         = $ENV{"INITIAL_TASK"}         || $ENV{"FIRST_TASK"} || "";

GetOptions(
    "openai-api-key=s"       => \$OPENAI_API_KEY,
    "openai-api-model=s"     => \$OPENAI_API_MODEL,
    "pinecone-api-key=s"     => \$PINECONE_API_KEY,
    "pinecone-environment=s" => \$PINECONE_ENVIRONMENT,
    "table-name=s"           => \$TABLE_NAME,
    "objective=s"            => \$OBJECTIVE,
    "initial-task=s"         => \$INITIAL_TASK,
) or die("Error in command line arguments\n");

# Environment variables
die "Missing OPENAI_API_KEY\n"       if !$OPENAI_API_KEY;
die "Missing OPENAI_API_MODEL\n"     if !$OPENAI_API_MODEL;
die "Missing PINECONE_API_KEY\n"     if !$PINECONE_API_KEY;
die "Missing PINECONE_ENVIRONMENT\n" if !$PINECONE_ENVIRONMENT;
die "Missing TABLE_NAME\n"           if !$TABLE_NAME;
die "Missing OBJECTIVE\n"            if !$OBJECTIVE;
die "Missing INITIAL_TASK\n"         if !$INITIAL_TASK;

if ( $OPENAI_API_MODEL =~ /gpt-4/i ) {
    print "\n*****USING GPT-4. POTENTIALLY EXPENSIVE. MONITOR YOUR COSTS*****\n";
}

print "\n*****OBJECTIVE*****\n";
print "$OBJECTIVE\n";
print "\nInitial task: $INITIAL_TASK\n";

# Initialize OpenAI API client
my $openai = OpenAPI::Client::OpenAI->new();

# Initialize Pinecone client
my $pinecone = OpenAPI::Client::Pinecone->new();

my $dimension = 1536;
my $metric    = "cosine";
my $pod_type  = "p1";

# Create Pinecone index
my $indexes = $pinecone->list_indexes()->res->json;

unless ( grep { $_ eq $TABLE_NAME } @$indexes ) {
    $pinecone->create_index(
        {
            name      => $TABLE_NAME,
            dimension => $dimension,
            metric    => $metric,
            pod_type  => $pod_type,
        }
    );
}

# Task list
my @task_list;

sub add_task {
    my ($task) = @_;
    push @task_list, $task;
}

sub get_ada_embedding {
    my ($text) = @_;
    $text =~ s/\n/ /g;
    return $openai->create_embedding({
        body => {
            model => "text-embedding-ada-002",
            input => $text,
        }
    })->res->json->{data}->[0]->{embedding};
}

sub openai_call {
    my (%args)      = @_;
    my $prompt      = $args{prompt};
    my $model       = $args{model}       || $OPENAI_API_MODEL;
    my $temperature = $args{temperature} || 0.5;
    my $max_tokens  = $args{max_tokens}  || 100;

    while (1) {
        my $response;
        if ( $model =~ /^llama/i ) {
            # Use llama as a subprocess
            die "Llama subprocess support not implemented in Perl";
        } elsif ( $model !~ /^gpt-/i ) {
            # Use completion API
            $response = $openai->create_completion({
                body => {
                    engine            => $model,
                    prompt            => $prompt,
                    temperature       => $temperature,
                    max_tokens        => $max_tokens,
                    top_p             => 1,
                    frequency_penalty => 0,
                    presence_penalty  => 0,
                }
            })->res->json;
            return $response->{choices}->[0]->{text};
        } else {
            # Use chat completion API
            my $messages = [ { role => "system", content => $prompt } ];
            $response = $openai->create_chat_completion({
                body => {
                    model       => $model,
                    messages    => $messages,
                    temperature => $temperature,
                    max_tokens  => $max_tokens,
                    n           => 1,
                    stop        => undef,
                }
            })->res->json;
            return $response->{choices}->[0]->{message}->{content};
        }
    }
}

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
    my $response  = openai_call( prompt => $prompt );
    my @new_tasks = split( "\n", $response );
    return map { { task_name => $_ } } @new_tasks;
}

sub prioritization_agent {
    my ($this_task_id) = @_;
    my @task_names     = map { $_->{task_name} } @task_list;
    my $next_task_id   = $this_task_id + 1;
    my $prompt         = <<"EOF";
You are a task prioritization AI tasked with cleaning the formatting of and reprioritizing the following tasks: @task_names.
Consider the ultimate objective of your team: $OBJECTIVE.
Do not remove any tasks. Return the result as a numbered list, like:
#. First task
#. Second task
Start the task list with number $next_task_id.
EOF
    my $response  = openai_call( prompt => $prompt );
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
    return openai_call( prompt => $prompt, temperature => 0.7, max_tokens => 2000 );
}

sub context_agent {
    my (%args)          = @_;
    my $query           = $args{query};
    my $n               = $args{n} || 5;
    my $query_embedding = get_ada_embedding($query);
    my $results         = $pinecone->query(
        {
            namespace        => $OBJECTIVE,
            query            => $query_embedding,
            top_k            => $n,
            include_metadata => 1,
        }
    );
    my $response_data  = $results->res->json;
    my @sorted_results = sort { $b->{score} <=> $a->{score} } @{ $response_data->{matches} };
    return map { $_->{metadata}->{task} } @sorted_results;
}

# Add the first task
my $first_task = { task_id => 1, task_name => $INITIAL_TASK };
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
        my $result       = execution_agent( $OBJECTIVE, $task->{task_name} );
        my $this_task_id = int( $task->{task_id} );
        print("\n*****TASK RESULT*****\n");
        print("$result\n");

        # Step 2: Enrich result and store in Pinecone
        my $enriched_result = { data => $result };                            # Enrich the result if needed
        my $result_id       = "result_$task->{task_id}";
        my $vector          = get_ada_embedding( $enriched_result->{data} )
            ;    # get vector of the actual result extracted from the dictionary

        $pinecone->upsert_vector(
            {
                namespace => $OBJECTIVE,
                items     => [ [ $result_id, $vector, { task => $task->{task_name}, result => $result } ] ],
            }
        );

        # Step 3: Create new tasks and reprioritize task list
        my @new_tasks =
            task_creation_agent( $OBJECTIVE, $enriched_result, $task->{task_name}, map { $_->{task_name} } @task_list );
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

=item * add_task - Adds a task to the task list

=item * get_ada_embedding - Retrieves an ADA embedding for the given text

=item * openai_call - Calls the OpenAI API for text generation

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
