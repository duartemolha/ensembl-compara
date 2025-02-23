=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2019] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut


=pod 

=head1 NAME

Bio::EnsEMBL::Compara::PipeConfig::HighConfidenceOrthologs_conf

=head1 SYNOPSIS

    init_pipeline.pl Bio::EnsEMBL::Compara::PipeConfig::HighConfidenceOrthologs_conf -compara_db mysql://...

=head1 DESCRIPTION

A simple pipeline to populate the high- and low- confidence levels on a Compara database

=head1 CONTACT

Please email comments or questions to the public Ensembl
developers list at <http://lists.ensembl.org/mailman/listinfo/dev>.

Questions may also be sent to the Ensembl help desk at
<http://www.ensembl.org/Help/Contact>.

=cut

package Bio::EnsEMBL::Compara::PipeConfig::HighConfidenceOrthologs_conf;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Version 2.4;

use Bio::EnsEMBL::Compara::PipeConfig::Parts::HighConfidenceOrthologs;

use base ('Bio::EnsEMBL::Compara::PipeConfig::ComparaGeneric_conf');


sub default_options {
    my ($self) = @_;
    return {
        %{ $self->SUPER::default_options() },               # inherit other stuff from the base class

        'high_confidence_capacity'    => 20,             # how many mlss_ids can be processed in parallel
        'high_confidence_batch_size'  => 10,            # how many mlss_ids' jobs can be batched together

    };
}

sub no_compara_schema {}    # Tell the base class not to create the Compara tables in the database

sub pipeline_analyses {
    my ($self) = @_;
    my $pipeline_analyses = Bio::EnsEMBL::Compara::PipeConfig::Parts::HighConfidenceOrthologs::pipeline_analyses_high_confidence($self);
    $pipeline_analyses->[0]->{'-input_ids'} = [
        {
            'compara_db'        => $self->o('compara_db'),
            'threshold_levels'  => $self->o('threshold_levels'),
        },
    ];

    return $pipeline_analyses;
}

1;

