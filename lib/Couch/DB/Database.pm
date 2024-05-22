# SPDX-FileCopyrightText: 2024 Mark Overmeer <mark@open-console.eu>
# SPDX-License-Identifier: EUPL-1.2-or-later

package Couch::DB::Database;

use Log::Report 'couch-db';

use Couch::DB::Util;

use Scalar::Util  qw(weaken);

=chapter NAME

Couch::DB::Database - One database connection

=chapter SYNOPSIS

   my $db = Couch::DB->db('my-db');

=chapter DESCRIPTION

=chapter METHODS

=section Constructors

=c_method new %options

=requires name STRING
The name must match C<< ^[a-z][a-z0-9_$()+/-]*$ >>.

=requires couch C<Couch::DB>-object
=cut

sub new(@) { my ($class, %args) = @_; (bless {}, $class)->init(\%args) }

sub init($)
{	my ($self, $args) = @_;

	my $name = $self->{CDD_name} = delete->{name} or panic "Requires name";
	$name =~ m!^[a-z][a-z0-9_$()+/-]*$!
		or error __x"Illegal database name '{name}'.", name => $name;

	$self->{CDD_couch} = delete $args->{couch} or panic "Requires couch";
	weaken $self->{CDD_couch};

	$self;
}

#-------------
=section Accessors
=cut

sub name()  { $_[0]->{CDD_name} }
sub couch() { $_[0]->{CDD_couch} }

#-------------
=section Database information
=cut

#XXX In the API 3.3.3 docs, sometime /db is used where /{db} is meant.

=method ping %options
[CouchDB API "HEAD /{db}", UNTESTED]
Check whether the database exists.  You may get some useful response headers.
=cut

sub ping(%)
{	my ($self, %args) = @_;

	$self->couch->call(HEAD => $self->_pathToDB,
		$self->couch->_resultsConfig(\%args),
	);
}

=method info %options
[CouchDB API "GET /{db}", UNTESTED]
Collect information from the database, for instance about its clustering.
=cut

sub info(%)
{	my ($self, %args) = @_;

	#XXX Value instance_start_time is now always zero, useful to convert if not
	#XXX zero in old nodes?

	$self->couch->call(GET => $self->_pathToDB,
		$self->couch->_resultsConfig(\%args),
	);
}

=method create %options
[CouchDB API "PUT /{db}", UNTESTED]
Create a new database.

=option  partitioned BOOLEAN
=default partitioned C<false>
Whether to create a paritioned database.
=cut

sub info(%)
{	my ($self, %args) = @_;

	my %query;
	$query{partitioned} = delete $args{partitioned} ? "true" : "false"
		exists $args{partitioned};

	$self->couch->call(PUT => $self->_pathToDB,
		query => \%query,
		$self->couch->_resultsConfig(\%args),
	);
}

=method delete %options
[CouchDB API "DELETE /{db}", UNTESTED]
Remove the database.
=cut

sub delete(%)
{	my ($self, %args) = @_;

	$self->couch->call(DELETE => $self->_pathToDB,
		$self->couch->_resultsConfig(\%args),
	);
}

=method userRoles %options
[CouchDB API "GET /{db}/_security", UNTESTED]
Returns the users who have access to the database, including their roles
(permissions).
=cut

sub userRoles(%)
{	my ($self, %args) = @_;

	$self->couch->call(GET => $self->_pathToDB('_security'),
		$self->couch->_resultsConfig(\%args),
	);
}

=method userRolesChange %options
[CouchDB API "PUT /{db}/_security", UNTESTED]
Returns the users who have access to the database, including their roles
(permissions).

=option  admin ARRAY
=default admin C<< [ ] >>

=option  members ARRAY
=default members C<< [ ] >>
=cut

sub userRolesChange(%)
{	my ($self, %args) = @_;
	my %send  = (
		admin   => delete $args{admin}   || [],
		members => delete $args{members} || [],
	);

	$self->couch->call(PUT => $self->_pathToDB('_security'),
		send  => { admin => 
		$self->couch->_resultsConfig(\%args),
	);
}

=method changes %options
[CouchDB API "GET /{db}/_changes", TODO] and
[CouchDB API "POST /{db}/_changes", TODO].
=cut

sub changes { ... }

=method compact %options
[CouchDB API "POST /{db}/_compact", UNTESTED],
[CouchDB API "POST /{db}/_compact/{ddoc}", UNTESTED]
Instruct the database files to be compacted.  By default, the data gets
compacted.

=option  ddoc $ddoc
=default ddoc C<undef>
Compact all indexes related to this design document.
=cut

sub compact(%)
{	my ($self, %args) = @_;
	my $path = $self->_pathToDB('_compact');

	if(my $ddoc = delete $args{ddoc})
	{	$path .= '/' . $ddoc->id;
	}

	$self->couch->call(POST => $path,
		$self->couch->_resultsConfig(\%args),
	);
}

=method ensureFullCommit %options
[CouchDB API "POST /{db}/_ensure_full_commit", deprecated 3.0.0, UNTESTED].
=cut

sub ensureFullCommit(%)
{	my ($self, %args) = @_;

	#XXX The 3.3.3 docs speak about "delayed_commits=true".  Where can I find
	#XXX older versions of this doc?

	$self->couch->call(POST => $self->_pathToDB('_ensure_full_commit'),
		deprecated => '3.0.0',
		$self->couch->_resultsConfig(\%args),
	);
}

=method purgeDocuments \%plan, %options
[CouchDB API "POST /{db}/_purge", UNTESTED].
Remove selected documents revisions from the database.

A deleted document is only marked as being deleted, but exists until
purge.  There must be sufficient time between deletion and purging,
to give replication a chance to distribute the fact of deletion.
=cut

sub purgeDocuments($%)
{	my ($self, $plan, %args) = @_;

	#XXX looking for smarter behavior here, to construct a plan.
	my $send = $plan;

	$self->couch->call(POST => $self->_pathToDB('_purge'),
		$self->couch->_resultsConfig(\%args),
	);
}

=method purgeRecordsLimit %options
[CouchDB API "GET /{db}/_purged_infos_limit", UNTESTED].
Returns the soft maximum number of records kept about deleting records.
=cut

#XXX seems not really a useful method.

sub purgeRecordsLimit(%)
{	my ($self, %args) = @_;

	$self->couch->call(GET => $self->_pathToDB('_purged_infos_limit'),
		$self->couch->_resultsConfig(\%args),
	);
}

=method purgeRecordsLimitSet $limit, %options
[CouchDB API "PUT /{db}/_purged_infos_limit", UNTESTED].
Set a new soft limit.  The default is 1000.
=cut

#XXX attribute of database creation

sub purgeRecordsLimitSet($%)
{	my ($self, $value, %args) = @_;

	$self->couch->call(PUT => $self->_pathToDB('_purged_infos_limit'),
		send => toInt($value),
		$self->couch->_resultsConfig(\%args),
	);
}

=method purgeUnusedViews %options
[CouchDB API "POST /{db}/_view_cleanup", UNTESTED].
=cut

sub purgeUnusedViews(%)
{	my ($self, %args) = @_;

	#XXX nothing to send?
	$self->couch->call(POST => $self->_pathToDB('_view_cleanup'),
		$self->couch->_resultsConfig(\%args),
	);
}

=method revisionsMissing \%plan, %options
[CouchDB API "POST /{db}/_missing_revs", UNTESTED].
With given a list of document revisions, returns the document revisions
that do not exist in the database.
=cut

sub revisionsMissing($%)
{	my ($self, $plan, %args) = @_;

	#XXX needs extra features
	$self->couch->call(POST => $self->_pathToDB('_missing_revs'),
		send => $plan,
		$self->couch->_resultsConfig(\%args),
	);
}

=method revisionsDiff \%plan, %options
[CouchDB API "POST /{db}/_revs_diff", UNTESTED].
With given a list of document revisions, returns the document revisions
that do not exist in the database.
=cut

sub revisionsDiff($%)
{	my ($self, $plan, %args) = @_;

	#XXX needs extra features
	$self->couch->call(POST => $self->_pathToDB('_revs_diff'),
		send => $plan,
		$self->couch->_resultsConfig(\%args),
	);
}

=method revisionLimit %options
[CouchDB API "GET /{db}/_revs_limit", UNTESTED].
Returns the soft maximum number of records kept about deleting records.
=cut

#XXX seems not really a useful method.

sub revisionLimit(%)
{	my ($self, %args) = @_;

	$self->couch->call(GET => $self->_pathToDB('_revs_limit'),
		$self->couch->_resultsConfig(\%args),
	);
}

=method revisionLimitSet $limit, %options
[CouchDB API "PUT /{db}/_revs_limit", UNTESTED].
Set a new soft limit.  The default is 1000.
=cut

#XXX attribute of database creation

sub revisionLimitSet($%)
{	my ($self, $value, %args) = @_;

	$self->couch->call(PUT => $self->_pathToDB('_revs_limit'),
		send => toInt($value),
		$self->couch->_resultsConfig(\%args),
	);
}

#-------------
=section Designs

=method listDesigns
[CouchDB API "GET /{db}/_design_docs", UNTESTED] and
[CouchDB API "POST /{db}/_design_docs", UNTESTED].
[CouchDB API "POST /{db}/_design_docs/queries", UNTESTED].
Get some design documents.

If there are searches, then C<GET> is used, otherwise the C<POST> version.
The returned structure depends on the searches and the number of searches.

=option  search \%query|ARRAY
=default search []
=cut

#XXX TODO  /db/_local_docs/queries

sub listDesigns(%)
{	my ($self, %args) = @_;
	my $couch   = $self->couch;

	my ($method, $path, $send) = (GET => $self->_pathToDB('_design_docs'), undef);
	my @search  = flat delete $args{search};
	if(@search)
	{	$method = 'POST';
	 	my @s;
		foreach (@search)
		{	my $s  = %$search;
			$couch->toJSON($s, bool => qw/conflicts descending include_docs inclusive_end update_seq/);
			push @s, $s;
		}
		if(@search==1)
		{	$send  = $search[0];
		}
		else
		{	$send  = +{ queries => \@search };
			$path .= '/queries';
		}
	}

	$self->couch->call($method => $path,
		($send ? (send => $send) : ()),
		$couch->_resultsConfig(\%args),
	);
}

#-------------
=section Indexes

=method createIndex %options
[CouchDB API "POST /{db}/_index", UNTESTED]
Create/confirm an index on the database.
=cut

sub createIndex(%)
{	my ($self, %args) = @_;
	my $couch  = $self->couch;

	my %config = $couch->_resultsConfig(\%args);
	my $send   = \%args;
	$couch->toJSON($send, bool => qw/partitioned/);

	$couch->call(POST => $self->_pathToDB('_index'),
		send => $send,
		%config,
	);
}

=method listIndexes %options
[CouchDB API "GET /{db}/_index", UNTESTED]
Collect all indexes for the database.
=cut

sub listIndexes(%)
{	my ($self, %args) = @_;

	$self->couch->call(GET => $self->_pathToDB('_index'),
		$self->couch->_resultsConfig(\%args),
	);
}

=method deleteIndex $ddoc, $name, %options
[CouchDB API "DELETE /{db}/_index/{designdoc}/json/{name}", UNTESTED]
=cut

sub deleteIndex($%)
{	my ($self, $ddoc, $name, %args) = @_;
	$self->couch->call(DELETE => $self->_pathToDB('_index/' . $ddoc->name . '/json/' . $name),
		$self->couch->_resultsConfig(\%args),
	);
}

=method explainSearch %options
[CouchDB API "POST /{db}/_explain", UNTESTED]
Explain how the a search will be executed.

=requires search HASH
=cut

sub explainSearch(%)
{	my ($self, %args) = @_;
	my $search = delete $args{search} or panic "Explain requires 'search'.";

	$self->couch->call(POST => $self->_pathToDB('_explain'),
		send => $search,
		$self->couch->_resultsConfig(\%args),
	);
}

#-------------
=section Handling documents

=method saveDocument $doc, %options
[CouchDB API "POST /{db}", UNTESTED]
Upload a document to this database.  The document is a M<Couch::DB::Document>.

=option  id   ID
=default id   generated
Every document needs an ID.  If not specified, it will get generated.

=option  batch BOOLEAN
=default batch C<false>
Do not wait for the write action to be completed.
=cut

sub __saved($$)
{	my ($self, $doc, $result) = @_;
	$result or return;

	my $v = $result->values;
	$doc->saved($v->{id}, $v->{rev});
}
	
sub saveDocument($%)
{	my ($self, $doc, %args) = @_;
	my %query;
	$query{batch} = 'ok' if delete $args{batch};

	my $data = $doc->data;
	$data->{_id} = delete $args{id} if defined $args{id};

	$self->couch->call(POST => $self->_pathToDB,
		send     => $data,
		on_final => sub { $self->__saved($doc, $_[0]) },
		$self->couch->_resultsConfig(\%args),
	);
}

=method updateDocuments \@docs, %options
[CouchDB API "POST /{db}/_bulk_docs", UNTESTED]
Insert, update, and delete multiple documents in one go.  This is more efficient
than saving them one by one.

Pass the documents which need to be save/updated in an ARRAY as first argument.

=option  new_edits BOOLEAN
=default new_edits C<true>
When false, than the docs will replace the existing revisions.

=option  delete $doc|\@docs
=default delete C<< [ ] >>
List of documents to remove.  You should not call the C<delete()> method on
them yourself!

=option  on_error CODE
=default on_error C<undef>
By default, errors are ignored.  When a CODE is specified, it will be called
with the result object, the failing document, and named parameters error details.
The %details contain the C<error> type, the error C<reason>, and the optional
C<deleting> boolean boolean.

=example for error handling
  sub handle($result, $doc, %details) { ... }
  $db->updateDocuments(@save, on_error => \&handle);
=cut

sub __updated($$$$)
{	my ($self, $result, $saves, $deletes, $on_error) = @_;
	$result or return;

	my %saves   = map +($_->id => $_), @$saves;
	my %deletes = map +($_->id => $_), @$deletes;

	foreach my $report (@{$result->values})
	{	my $id    = $report->{id};
		my ($doc, $delete);
		if($doc = delete $deletes{$id}) { $delete = 1 }
		else { $doc = delete $docs{$id} or panic "missing report for updated $id" }

		if($report->{ok})
		{	$doc->saved($id, $report->{rev});
			$doc->deleted if $delete;
		}
		else
		{	$on_error->($result, $doc, +{ %$report, delete => $delete };
		}
	}

	$on_error->($result, $_, { error => 'missing', reason => "The server did not report back on saving $id." })
		for values %saves;

	$on_error->($result, $_, { error => 'missing', reason => "The server did not report back on deleting $id.", delete => 1 })
		for values %deletes;
}

sub updateDocuments($%)
{	my ($self, $docs, %args) = @_;
	my $couch   = $self->couch;

	my @plan    = map $_->data, @$docs;
	my @deletes = flat delete $args{delete};

	foreach my $del (@deletes)
	{	push @plan, +{ _id => $del->id, _rev => $del->rev, _delete => true };
	}

	@plan or error __x"need at least on document for bulk processing.";
	my %send    = ( docs => \@plan );

	$send{new_edits} = delete $args{new_edits} ? 'true' : 'false'
		if exists $args{new_edits};

	$couch->call(POST => $self->_pathToDB('_bulk_docs'),
		send     => \%send,
		on_final => sub { $self->_updated($_[0], $docs, \@deletes) },
		$couch->_resultsConfig(\%args),
	);
}

=method inspectDocuments \@docs, %options
[CouchDB API "POST /{db}/_bulk_get", UNTESTED]
Return information on multiple documents at the same time.

=option  revs BOOLEAN
=default revs C<false>
Include the revision history of each document.
=cut

sub inspectDocuments($%)
{	my ($self, $docs, %args) = @_;

	my %query;
	$query{revs} = delete $args{revs} ? 'true' : 'false' if exists $args{revs};

	@$docs or error __x"need at least on document for bulk query.";

	#XXX what does "conflicted documents mean?
	#XXX what does "a": 1 mean in its response?

	$self->couch->call(POST =>  $self->_pathToDB('_bulk_get'),
		send => { docs => $docs },
		$couch->_resultsConfig(\%args),
	);
}

=method listDocuments %options
[CouchDB API "GET /{db}/_all_docs", UNTESTED],
[CouchDB API "POST /{db}/_all_docs", UNTESTED], and
[CouchDB API "POST /{db}/_all_docs/queries", UNTESTED].
Get the documents, optionally limited by a view.

If there are searches, then C<GET> is used, otherwise the C<POST> version.
The returned structure depends on the searches and the number of searches.

=option  search \%view|ARRAY
=default search []

=cut

#XXX refer to the view parameter docs

sub listDocuments(%)
{	my ($self, %args) = @_;
	my @search = flat delete $args{search};

	my ($method, $path, $send) = (GET => $self->_pathToDB('_all_docs'), undef);
	if(@search)
	{	$method = 'POST';
		if(@search==1)
		{	$send = $search[0];
		}
		else
		{	$send = +{ queries => \@search };
			$path .= '/queries';
		}
	}

	$self->couch->call($method => $path,
		$self->couch->_resultsConfig(\%args),
	);
}

=method find %options
[CouchDB API "POST /{db}/_find", UNTESTED]
Search the database for matching components.
=cut

sub find(%)
{	my ($self, %args) = @_;
	my $couch  = $self->couch;

	my %config = $couch->_resultsConfig(\%args);
	my $send   = \%args;
	$couch->toJSON($send, bool => qw/conflicts update stable execution_stats/);

	$couch->call(POST => $self->_pathToDB('_find'),
		send => $send,
		%config,
	);
}

#-------------
=section Other
=cut

1;