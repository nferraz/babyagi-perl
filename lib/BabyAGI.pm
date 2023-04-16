package BabyAGI;

use strict;
use warnings;

use Exporter;

use Time::HiRes qw( sleep );

use Dotenv;
use OpenAPI::Client::OpenAI;
use OpenAPI::Client::Pinecone;

our $VERSION = '0.01';

# Load environment variables from .env file
Dotenv->load();

sub new {
    my $class = shift;
    my $args  = ref $_[0] ? $_[0] : {@_};

    $args->{OPENAI_API_KEY}       = $ENV{"OPENAI_API_KEY"}       || "";
    $args->{OPENAI_API_MODEL}     = $ENV{"OPENAI_API_MODEL"}     || "gpt-3.5-turbo";
    $args->{PINECONE_API_KEY}     = $ENV{"PINECONE_API_KEY"}     || "";
    $args->{PINECONE_ENVIRONMENT} = $ENV{"PINECONE_ENVIRONMENT"} || "";
    $args->{TABLE_NAME}           = $ENV{"TABLE_NAME"}           || "";
    $args->{OBJECTIVE}            = $ENV{"OBJECTIVE"}            || "";
    $args->{INITIAL_TASK}         = $ENV{"INITIAL_TASK"}         || $ENV{"FIRST_TASK"} || "";

    # Environment variables
    die "Missing OPENAI_API_KEY\n"       if !$args->{OPENAI_API_KEY};
    die "Missing OPENAI_API_MODEL\n"     if !$args->{OPENAI_API_MODEL};
    die "Missing PINECONE_API_KEY\n"     if !$args->{PINECONE_API_KEY};
    die "Missing PINECONE_ENVIRONMENT\n" if !$args->{PINECONE_ENVIRONMENT};
    die "Missing TABLE_NAME\n"           if !$args->{TABLE_NAME};
    die "Missing OBJECTIVE\n"            if !$args->{OBJECTIVE};
    die "Missing INITIAL_TASK\n"         if !$args->{INITIAL_TASK};

    if ( $args->{OPENAI_API_MODEL} =~ /gpt-4/i ) {
        print "\n*****USING GPT-4. POTENTIALLY EXPENSIVE. MONITOR YOUR COSTS*****\n";
    }

    print "\n*****OBJECTIVE*****\n";
    print "$args->{OBJECTIVE}\n";
    print "\nInitial task: $args->{INITIAL_TASK}\n";

    return bless $args, $class;
}

sub openai {
    my $self = shift;
    $self->{openai} //= OpenAPI::Client::OpenAI->new();
}

sub pinecone {
    my $self = shift;
    return $self->{pinecone} if defined $self->{pinecone};

    $self->{pinecone} = OpenAPI::Client::Pinecone->new();
    my $dimension = 1536;
    my $metric    = "cosine";
    my $pod_type  = "p1";

    # Create Pinecone index
    my $indexes = $self->{pinecone}->list_indexes()->res->json;

    unless ( grep { $_ eq $self->{TABLE_NAME} } @$indexes ) {
        $self->{pinecone}->create_index(
            {
                name      => $self->{TABLE_NAME},
                dimension => $dimension,
                metric    => $metric,
                pod_type  => $pod_type,
            }
        );
    }

    return $self->{pinecone};
}

sub generate_ideas {
    my ( $self, %args ) = @_;

    my $prompt      = $args{prompt};
    my $model       = $args{model}       || $self->{OPENAI_API_MODEL};
    my $temperature = $args{temperature} || 0.5;
    my $max_tokens  = $args{max_tokens}  || 100;

    while (1) {
        my $response;
        if ( $model =~ /^llama/i ) {
            # Use llama as a subprocess
            die "Llama subprocess support not implemented in Perl";
        } elsif ( $model !~ /^gpt-/i ) {
            # Use completion API
            $response = $self->openai->create_completion(
                {
                    body => {
                        engine            => $model,
                        prompt            => $prompt,
                        temperature       => $temperature,
                        max_tokens        => $max_tokens,
                        top_p             => 1,
                        frequency_penalty => 0,
                        presence_penalty  => 0,
                    }
                }
            )->res->json;
            return $response->{choices}->[0]->{text};
        } else {
            # Use chat completion API
            my $messages = [ { role => "system", content => $prompt } ];
            $response = $self->openai->create_chat_completion(
                {
                    body => {
                        model       => $model,
                        messages    => $messages,
                        temperature => $temperature,
                        max_tokens  => $max_tokens,
                        n           => 1,
                        stop        => undef,
                    }
                }
            )->res->json;
            return $response->{choices}->[0]->{message}->{content};
        }
    }
}

sub study_text {
    my ( $self, $text ) = @_;

    $text =~ s/\n/ /g;
    return $self->openai->create_embedding(
        {
            body => {
                model => "text-embedding-ada-002",
                input => $text,
            }
        }
    )->res->json->{data}->[0]->{embedding};
}

sub memorize {
    my ( $self, %args ) = @_;

    my $task   = $args{task};
    my $result = $args{result};

    my $enriched_result = { data => $result };         # Enrich the result if needed
    my $result_id       = "result_$task->{task_id}";

    # get vector of the actual result extracted from the dictionary
    my $vector = $self->study_text( $enriched_result->{data} );

    $self->pinecone->upsert_vector(
        {
            namespace => $self->{OBJECTIVE},
            items     => [ [ $result_id, $vector, { task => $task->{task_name}, result => $result } ] ],
        }
    );

    return $enriched_result;
}

sub recall {
    my ( $self, %args ) = @_;
    my $query = $args{query};
    my $n     = $args{n} || 5;

    my $query_embedding = $self->study_text($query);

    my $results = $self->pinecone->query(
        {
            namespace        => $self->{OBJECTIVE},
            query            => $query_embedding,
            top_k            => $n,
            include_metadata => 1,
        }
    );
    my $response_data = $results->res->json;
}

1;
