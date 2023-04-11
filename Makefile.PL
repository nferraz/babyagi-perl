#!/usr/bin/env perl

use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME          => 'BabyAGI',
    AUTHOR        => 'Nelson Ferraz <nferraz@gmail.com>',
    VERSION_FROM  => 'bin/babyagi.pl',
    ABSTRACT      => 'BabyAGI in Perl',
    LICENSE       => 'artistic_2',
    PREREQ_PM     => {
        'Dotenv'                    => 0,
        'OpenAPI::Client::Pinecone' => 0,
        'OpenAPI::Client::OpenAI'   => 0,
    },
    EXE_FILES => ['myscript.pl'],
);
