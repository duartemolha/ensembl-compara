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


=head1 NAME

Bio::EnsEMBL::Compara::PipeConfig::EPO_pt1_conf

=head1 SYNOPSIS

    #1. Update ensembl-hive, ensembl and ensembl-compara GIT repositories before each new release

    #3. Check all default_options, you will probably need to change the following :
        pipeline_db (-host)
        resource_classes 

	'compara_pairwise_db' - I'm assuiming that all of your pairwise alignments are in one compara db
	'reference_genome_db_name' - the production name of the species which is in all your pairwise alignments
	'main_core_dbs' - the servers(s) hosting most/all of the core (species) dbs
	'core_db_urls' - any additional core dbs (not in 'main_core_dbs')
        The dummy values - you should not need to change these unless they clash with pre-existing values associated with the pairwise alignments you are going to use

    #4. Run init_pipeline.pl script:
        Using command line arguments:
        init_pipeline.pl Bio::EnsEMBL::Compara::PipeConfig::EPO_pt1_conf.pm

    #5. Run the "beekeeper.pl ... -sync" and then " -loop" command suggested by init_pipeline.pl

    #6. Fix the code when it crashes

=head1 DESCRIPTION  

    This configuaration file gives defaults for the first part of the EPO pipeline (this part generates the anchors from pairwise alignments). 

=head1 CONTACT

Please email comments or questions to the public Ensembl
developers list at <http://lists.ensembl.org/mailman/listinfo/dev>.

Questions may also be sent to the Ensembl help desk at
<http://www.ensembl.org/Help/Contact>.

=cut

package Bio::EnsEMBL::Compara::PipeConfig::EPO_pt1_conf;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Version 2.4;

use base ('Bio::EnsEMBL::Compara::PipeConfig::ComparaGeneric_conf');

sub default_options {
    my ($self) = @_;

    return {
      	%{$self->SUPER::default_options},
        'pipeline_name' => 'generate_anchors_' . $self->o('species_set_name').'_'.$self->o('rel_with_suffix'),

      	# parameters that are likely to change from execution to another:
      	'core_db_version' => 88, # version of the dbs from which to get the pairwise alignments
      	
      	# alignment chunk size
      	'chunk_size' => 100000000,
      	# max block size for pecan to align
      	'pecan_block_size' => 1000000,

      	'max_frag_diff' => 1.5, # max difference in sizes between non-reference dnafrag and reference to generate the overlaps from
      	'min_ce_length' => 40, # min length of each sequence in the constrained elenent 
        'min_anchor_size' => 50, # at least one of the sequences in an anchor must be of this size
      	'max_anchor_seq_len' => 100, # anchors longer than this value will be trimmed
      	'min_number_of_seqs_per_anchor' => 2, # minimum number of sequences in an anchor
      	'max_number_of_seqs_per_anchor' => 30, # maximum number of sequences in an anchor - can happen due to duplicates or repeats
    };
}

sub pipeline_wide_parameters {
	my $self = shift @_;
	return {
		%{$self->SUPER::pipeline_wide_parameters},

		'compara_pairwise_db' => $self->o('compara_pairwise_db'),
                'mlss_id'        => $self->o('mlss_id'),
		# 'main_core_dbs' => $self->o('main_core_dbs'),
                # 'additional_core_db_urls' => $self->o('additional_core_db_urls'),
		'min_anchor_size' => $self->o('min_anchor_size'),
		'min_number_of_seqs_per_anchor' => $self->o('min_number_of_seqs_per_anchor'),
		'max_number_of_seqs_per_anchor' => $self->o('max_number_of_seqs_per_anchor'),
		'max_frag_diff' => $self->o('max_frag_diff'),
	        'reference_genome_db_name' => $self->o('reference_genome_db_name'),
                'genome_dumps_dir'      => $self->o('genome_dumps_dir'),
	};
	
}

sub pipeline_analyses {
	my ($self) = @_;
return [
# ------------------------------------- set up the necessary database tables

    {
        -logic_name => 'populate_new_database',
        -module     => 'Bio::EnsEMBL::Compara::RunnableDB::GenomicAlignBlock::PopulateNewDatabase',
        -parameters => {
            'program'        => $self->o('populate_new_database_exe'),
            'pipeline_db'    => $self->pipeline_url(),
            'reg_conf'       => $self->o('reg_conf'),
            'master_db'      => $self->o('master_db'),
        },
        -input_ids => [{}],
        -flow_into => [ 'set_genome_db_locator_factory' ],
    },

    {
        -logic_name => 'set_genome_db_locator_factory',
        -module     => 'Bio::EnsEMBL::Compara::RunnableDB::GenomeDBFactory',
        -flow_into  => {
            '2->A' => [ 'update_genome_db_locator' ],
            '1->A' => [ 'make_species_tree' ],
            'A->1' => [ 'chunk_reference_dnafrags_factory' ],
        }
    },

{ # this sets up the locator field in the genome_db table
 -logic_name => 'update_genome_db_locator',
 -module     => 'Bio::EnsEMBL::Compara::Production::EPOanchors::UpdateGenomeDBLocator',
},

{
 -logic_name    => 'make_species_tree',
 -module        => 'Bio::EnsEMBL::Compara::RunnableDB::MakeSpeciesTree',
 -parameters    => {
   'species_tree_input_file' => $self->o('binary_species_tree'),
 },
 -flow_into     => [ 'set_gerp_neutral_rate' ],
},


        {   -logic_name => 'set_gerp_neutral_rate',
            -module     => 'Bio::EnsEMBL::Compara::RunnableDB::GenomicAlignBlock::SetGerpNeutralRate',
            -flow_into => {
                2 => [ '?table_name=pipeline_wide_parameters' ],
            },
        },

# ------------------------------------- now for the modules which create the anchors

{ # split the reference genome in to convenient sized frags for parallelisation
 -logic_name	=> 'chunk_reference_dnafrags_factory',
 -module		=> 'Bio::EnsEMBL::Compara::Production::EPOanchors::ChunkRefDnaFragsFactory',
 -parameters	=> {
   'chunk_size' => $self->o('chunk_size'),
 },
 -flow_into	=> {
	'2->A' => [ 'find_pairwise_overlaps' ],
	'A->1' => [ 'transfer_ce_data_to_anchor_align' ],
  },
},

{ # finds the overlaps between the pairwise lignments and populates the dnafrag_region and synteny_region tables with the overlaps  
 -logic_name	=> 'find_pairwise_overlaps',
 -module		=> 'Bio::EnsEMBL::Compara::Production::EPOanchors::FindPairwiseOverlaps',
 -flow_into	=> {
		2 => [ 'pecan' ],
		3 => [ '?table_name=dnafrag_region&insertion_method=INSERT_IGNORE' ],
	},
 -hive_capacity => 50,
 -batch_size    => 20,
},

{ # align the overlapping regions - creates entries in the genomic_align and genomic_align_block tables
 -logic_name    => 'pecan',
 -module        => 'Bio::EnsEMBL::Compara::RunnableDB::MercatorPecan::Pecan',
 -parameters    => { 
  'max_block_size' => $self->o('pecan_block_size'),
  'java_options' => '-server -Xmx1000M',
  'exonerate_exe'       => $self->o('exonerate_exe'),
  'pecan_exe_dir'       => $self->o('pecan_exe_dir'),
  'estimate_tree_exe'   => $self->o('estimate_tree_exe'),
  'java_exe'            => $self->o('java_exe'),
  'ortheus_py'          => $self->o('ortheus_py'),
  'ortheus_lib_dir'     => $self->o('ortheus_lib_dir'),
  'ortheus_bin_dir'     => $self->o('ortheus_bin_dir'),
  'semphy_exe'          => $self->o('semphy_exe'),
   },
 -flow_into      => {
		2 => [ 'pecan_high_mem' ],  # Pecan complained
		-1 => [ 'pecan_high_mem' ],  # LSF killed because of MEMLIMIT
		1 => [ 'gerp_constrained_element' ],
   },
 -hive_capacity => 300,
 -max_retry_count => 1,
},

{    
 -logic_name => 'pecan_high_mem',
 -parameters => {
   'max_block_size' => $self->o('pecan_block_size'),
   java_options => '-server -Xmx6000M',
   'exonerate_exe'       => $self->o('exonerate_exe'),
   'pecan_exe_dir'       => $self->o('pecan_exe_dir'),
   'estimate_tree_exe'   => $self->o('estimate_tree_exe'),
   'java_exe'            => $self->o('java_exe'),
   'ortheus_py'          => $self->o('ortheus_py'),
   'ortheus_lib_dir'     => $self->o('ortheus_lib_dir'),
   'ortheus_bin_dir'     => $self->o('ortheus_bin_dir'),
   'semphy_exe'          => $self->o('semphy_exe'),
 },  
 -module => 'Bio::EnsEMBL::Compara::RunnableDB::MercatorPecan::Pecan',
 -hive_capacity => 300,
 -rc_name => '8Gb_job',
 -max_retry_count => 1,
 -flow_into      => {
		1 => [ 'gerp_constrained_element' ],
   },
},  

{ # find the most highly constrained regions from the aligned overlaps - this will create entries in the constrained element table
 -logic_name    => 'gerp_constrained_element',
 -module => 'Bio::EnsEMBL::Compara::RunnableDB::GenomicAlignBlock::Gerp',
 -parameters    => { 'window_sizes' => [1,10,100,500], 'gerp_exe_dir' => $self->o('gerp_exe_dir'),
     'constrained_element_method_link_type' => 'EPO_GEN_ANCHORS', 'no_conservation_scores' => 1,
    },
 -hive_capacity => 100,
 -batch_size    => 10,
},

{ # copies the constrained element data to the anchor_align table 
 -logic_name     => 'transfer_ce_data_to_anchor_align',
 -module         => 'Bio::EnsEMBL::Hive::RunnableDB::SqlCmd',
 -parameters => {
   'sql' => [
		'INSERT INTO anchor_align (method_link_species_set_id, anchor_id, dnafrag_id, dnafrag_start, dnafrag_end, dnafrag_strand) '.
		'SELECT method_link_species_set_id, constrained_element_id, dnafrag_id, dnafrag_start, dnafrag_end, dnafrag_strand FROM '. 
		'constrained_element WHERE (dnafrag_end - dnafrag_start + 1) >= '. $self->o('min_ce_length') .' ORDER BY constrained_element_id',
	],
  },
 -flow_into      => { 1 => 'trim_anchor_align_factory' },
},

{ 
 -logic_name => 'trim_anchor_align_factory',
 -module     => 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
 -parameters => {
    'inputquery'      => "SELECT DISTINCT(anchor_id) AS anchor_id FROM anchor_align WHERE method_link_species_set_id = #mlss_id# AND untrimmed_anchor_align_id IS NULL",
 },  
 -flow_into => {
    '2->A' => [ 'trim_anchor_align' ],
    'A->1' => [ 'load_anchor_sequence_factory' ],
 },  
},  

{ # finds the best cut position within an anchor and trims the anchor positions down to 2 base pairs - it populates the anchor_align table with these trimmed anchors
 -logic_name => 'trim_anchor_align',			
 -module     => 'Bio::EnsEMBL::Compara::Production::EPOanchors::TrimAnchorAlign',
 -parameters => {
    'method_link_species_set_id' => '#mlss_id#',
    'ortheus_c_exe' => $self->o('ortheus_c_exe'),
  },
 -hive_capacity => 100,
 -batch_size    => 10,
 -flow_into     => {
     -1 => [ 'trim_anchor_align_himem' ],
 }
},

{ # finds the best cut position within an anchor and trims the anchor positions down to 2 base pairs - it populates the anchor_align table with these trimmed anchors
 -logic_name => 'trim_anchor_align_himem',
 -module     => 'Bio::EnsEMBL::Compara::Production::EPOanchors::TrimAnchorAlign',
 -parameters => {
    'method_link_species_set_id' => '#mlss_id#',
    'ortheus_c_exe' => $self->o('ortheus_c_exe'),
  },
 -rc_name => '8Gb_job',
 -hive_capacity => 100,
 -batch_size    => 10,
},

{ 
 -logic_name => 'load_anchor_sequence_factory',
 -module     => 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
 -parameters => {
	'inputquery'  => 'SELECT DISTINCT(anchor_id) AS anchor_id FROM anchor_align WHERE method_link_species_set_id = #mlss_id# AND untrimmed_anchor_align_id IS NOT NULL',
  },
 -flow_into => {
	2 => [ 'load_anchor_sequence' ],	
  }, 
},	

{ # using the anchor positions from 'trim_anchor_align' it populates the anchor_sequence table with anchor sequences between min_ce_length and max_anchor_seq_len (using the 2bp trim coord as a mid-point 
 -logic_name => 'load_anchor_sequence',
 -module     => 'Bio::EnsEMBL::Compara::Production::EPOanchors::LoadAnchorSequence',
 -parameters => {
    'input_method_link_species_set_id' => '#mlss_id#',
    'max_anchor_seq_len' => $self->o('max_anchor_seq_len'),
    'min_anchor_seq_len' => $self->o('min_ce_length'),
 },
 -batch_size    => 10,
 -hive_capacity => 10,
},
];
}	


1;
