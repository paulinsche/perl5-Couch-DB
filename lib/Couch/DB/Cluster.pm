# SPDX-FileCopyrightText: 2024 Mark Overmeer <mark@open-console.eu>
# SPDX-License-Identifier: EUPL-1.2-or-later

package Couch::DB::Cluster;

use Couch::DB::Util;

use Log::Report 'couch-db';

use Scalar::Util  qw(weaken);

=chapter NAME

Couch::DB::Cluster - interface for cluster management

=chapter SYNOPSIS

  my $cluster = $couchdb->cluster;

=chapter DESCRIPTION
This modules groups all CouchDB API calls which relate to clustering, replication, and
related jobs.  There are too many related methods, so they got their own module.

=chapter METHODS

=section Constructors

=c_method new %options
=requires couch C<Couch::DB>-object

=cut

sub new(@) { my ($class, %args) = @_; (bless {}, $class)->init(\%args) }

sub init($)
{   my ($self, $args) = @_;

    $self->{CDC_couch} = delete $args->{couch} or panic "Requires couch";
    weaken $self->{CDC_couch};

    $self;
}


#-------------
=section Accessors
=method couch
=cut

sub couch() { $_[0]->{CDC_couch} }

#-------------
=section Managing a Cluster

=method clusterState %options
[CouchDB API "GET /_cluster_setup", since 2.0, UNTESTED]
Describes the status of this CouchDB instance is in the cluster.

Option C<ensure_dbs_exist>.
=cut

sub clusterState(%)
{	my ($self, %args) = @_;

	$args{client} || @{$args{client} || []}==1
		or error __x"Explicitly name one client for clusterState().";

	my %query;
	my @need = flat delete $args{ensure_dbs_exists};
	$query{ensure_dbs_exists} = $self->couch->jsonText(\@need, compact => 1)
		if @need;

	$self->couch->call(GET => '/_cluster_setup',
		introduced => '2.0',
		$self->couch->_resultsConfig(\%args),
		query      => \%query,
	);
}

=method clusterSetup %options
[CouchDB API "POST /_cluster_setup", since 2.0, UNTESTED]
Describes the status of this CouchDB instance is in the cluster.

All %options are posted as parameters.  See the API docs.
=cut

sub clusterSetup(%)
{	my ($self, %args) = @_;

	$args{client} || @{$args{client} || []}==1
		or error __x"Explicitly name one client for clusterSetup().";

	$self->couch->call(POST => '/_cluster_setup',
		introduced => '2.0',
		$self->couch->_resultsConfig(\%args),
		send       => \%args,
	);
}

=method reshardStatus %options
[CouchDB API "GET /_reshard", since 2.4, UNTESTED] and
[CouchDB API "GET /_reshard/state", since 2.4, UNTESTED]

=option  counts BOOLEAN
=default counts C<false>
Include the job counts in the result.
=cut

#XXX The example in CouchDB API doc 3.3.3 says it returns 'reason' with /state,
#XXX but the spec says 'state_reason'.

sub reshardStatus(%)
{	my ($self, %args) = @_;
	my $path = '/_reshard';
	$path   .= '/state' if delete $args{counts};

	$self->couch->call(GET => $path,
		introduced => '2.4',
		$self->couch->_resultsConfig(\%args),
	);
}

=method resharding %options
[CouchDB API "PUT /_reshard/state", since 2.4, UNTESTED]
Start or stop the resharding process.

=requires state STRING
Can be C<stopped> or C<running>.  Stopped state can be resumed into running.

=option   reason STRING
=default  reason C<undef>

=cut

#XXX The example in CouchDB API doc 3.3.3 says it returns 'reason' with /state,
#XXX but the spec says 'state_reason'.

sub resharding(%)
{	my ($self, %args) = @_;

	my %send   = (
		state  => (delete $args{state} or panic "Requires 'state'"),
		reason => delete $args{reason},
	);

	$self->couch->call(PUT => '/_reshard/state',
		introduced => '2.4',
		send       => \%send,
		$self->couch->_resultsConfig(\%args),
	);
}

=method reshardJobs %options
[CouchDB API "GET /_reshard/jobs", since 2.4, UNTESTED]
Show the resharding activity.
=cut

sub __jobValues($$)
{	my ($couch, $job) = @_;

	$couch->toPerl($job, isotime => qw/start_time update_time/)
	      ->toPerl($job, node => qw/node/);

	$couch->toPerl($_, isotime => qw/timestamp/)
		for @{$job->{history} || []};
}

sub __reshardJobsValues($$)
{	my ($result, $data) = @_;
	my $couch  = $result->couch;

	my $values = dclone $data;
	__jobValues($couch, $_) for @{$values->{jobs} || []};
	$values;
}

sub reshardJobs(%)
{	my ($self, %args) = @_;

	$self->couch->call(GET => '/_reshard/jobs',
		introduced => '2.4',
		$self->couch->_resultsConfig(\%args),
		to_values  => \&__reshardJobsValues,
	);
}

=method reshardCreate %options
[CouchDB API "POST /_reshard/jobs", since 2.4, UNTESTED]
Create resharding jobs.

The many %options are passed as parameters.
=cut

sub __reshardCreateValues($$)
{	my ($result, $data) = @_;
	my $values = dclone $data;
	$result->couch->toPerl($_, node => 'node')
		for @$values;

	$values;
}

sub reshardCreate(%)
{	my ($self, %args) = @_;
	my %config = $self->couch->_resultsConfig(\%args);

	#XXX The spec in CouchDB API doc 3.3.3 lists request param 'node' twice.

	$self->couch->call(POST => '/_reshard/jobs',
		introduced => '2.4',
		send       => \%args,
		to_values  => \&__reshardCreateValues,
		%config,
	);
}

=method reshardJob $jobid, %options
[CouchDB API "GET /_reshard/jobs/{jobid}", since 2.4, UNTESTED]
Show the resharding activity.
=cut

sub __reshardJobValues($$)
{	my ($result, $data) = @_;
	my $couch  = $result->couch;

	my $values = dclone $data;
	__jobValues($couch, $values);
	$values;
}

sub reshardJob($%)
{	my ($self, $jobid, %args) = @_;

	$self->couch->call(GET => "/_reshard/jobs/$jobid",
		introduced => '2.4',
		$self->couch->_resultsConfig(\%args),
		to_values  => \&__reshardJobValues,
	);
}

=method reshardJobRemove $jobid, %options
[CouchDB API "DELETE /_reshard/jobs/{jobid}", since 2.4, UNTESTED]
Show the resharding activity.
=cut

sub reshardJobRemove($%)
{	my ($self, $jobid, %args) = @_;

	$self->couch->call(DELETE => "/_reshard/jobs/$jobid",
		introduced => '2.4',
		$self->couch->_resultsConfig(\%args),
	);
}

=method reshardJobState $jobid, %options
[CouchDB API "GET /_reshard/jobs/{jobid}/state", since 2.4, UNTESTED]
Show the resharding job status.
=cut

sub reshardJobState($%)
{	my ($self, $jobid, %args) = @_;

	#XXX in the 3.3.3 docs, "Request JSON Object" should read "Response ..."
	$self->couch->call(GET => "/_reshard/job/$jobid/state",
		introduced => '2.4',
		$self->couch->_resultsConfig(\%args),
	);
}

=method reshardJobChange $jobid, %options
[CouchDB API "PUT /_reshard/jobs/{jobid}/state", since 2.4, UNTESTED]
Change the resharding job status.

=requires state STRING
Can be C<new>, C<running>, C<stopped>, C<completed>, or C<failed>.

=option   reason STRING
=default  reason C<undef>
=cut

sub reshardJobChange($%)
{	my ($self, $jobid, %args) = @_;

	my %send = (
		state  => (delete $args{state} or panic "Requires 'state'"),
		reason => delete $args{reason},
	);

	$self->couch->call(PUT => "/_reshard/job/$jobid/state",
		introduced => '2.4',
		send       => \%send,
		$self->couch->_resultsConfig(\%args),
	);
}


#-------------
=section Other
=cut

1;
