package FusionInventory::Agent::Task::Deploy::UserCheck;

use strict;
use warnings;

use English qw(-no_match_vars);
use UNIVERSAL::require;

# Supported sub-class must be declared here
my %Supported_UserCheck_Modules = (
    MSWin32 => "WTS"
);

# Supported values as platform check key 
my %supported_platform_keys = (
    win32 => "MSWin32", # Value is $OSNAME expected value for platform
    macos => "darwin",
    linux => "linux",

    # Convenient platform alias to match any platform
    any   => "ALL",

    # Convenient platform alias to avoid undefined values on check
    none  => "None"
);

my @supported_keys = qw(
    type text title icon buttons timeout wait platform
    on_ok on_cancel on_yes on_no on_retry on_try on_abort
    on_timeout on_nouser
);

sub new {
    my ($class, %params) = @_;

    my $self = {
        logger      => $params{logger},
        type        => 'after',
        platform    => 'any',
        _stopped    => 0,

        _on_event   => undef,
        # Default "on_<event>" definitions
        _on_error   => 'stop:agent_failure:',
        _on_none    => 'stop:error_no_event:',
        _on_nouser  => 'continue:nouser:',
        _on_unknown => 'stop:event_failure:',

        _status     => {}
    };

    bless $self, $class;

    unless ($Supported_UserCheck_Modules{$OSNAME}) {
        $self->debug("user interaction not supported on $OSNAME platform");
        return undef;
    }

    if ($params{check} && ref($params{check}) eq 'HASH') {
        foreach my $key (@supported_keys) {
            next unless (defined($params{check}->{$key}));
            if ($key =~ /^on_/) {
                # Keep event values as private to avoid coding confusion
                $self->{"_$key"} = $params{check}->{$key};
                next;
            }
            $self->{$key} = $params{check}->{$key};
        }
    }

    # Check if we are on a requested platform
    my %requested_on = map { $supported_platform_keys{lc($_ || 'none')} => 1 } split(',', $self->{platform});
    unless ($requested_on{ALL} || $requested_on{$OSNAME}) {
        $self->debug("user interaction requested on '$self->{platform}', not on this $OSNAME platform");
        return undef;
    }

    my $module = $class . '::' . $Supported_UserCheck_Modules{$OSNAME};
    $module->require();
    if ($EVAL_ERROR) {
        $self->error("Can't use $module module: load failure ($EVAL_ERROR)");
        return undef;
    } else {
        bless $self, $module;
    }

    return $self;
}

sub tagged {
    my ($self, $message) = @_;

    return "usercheck $self->{type}: $message";
}

sub debug2 {
    my ($self, $message) = @_;

    $self->{logger}->debug2($self->tagged($message)) if $self->{logger};
}

sub debug {
    my ($self, $message) = @_;

    $self->{logger}->debug($self->tagged($message)) if $self->{logger};
}

sub handle_event {
    # Debug and set handled event for later user in status_for_server API
    my ($self, $event, $message) = @_;

    $self->debug($message) if $message;

    my $policy = $self->{"_$event"};
    if (defined($policy)) {
        $self->debug2("$event event: applying policy: $policy");
    } else {
        $policy = "stop:error_bad_event";
        $self->error("Unsupported $event event: setting policy to $policy");
        $self->{"_$event"} = $policy;
    }

    # Store event as this defines the expected server status
    $self->{_on_event} = $event;

    return $self->continue()
        if ($policy =~ /^continue:/);

    $self->error("$event event: unsupported local $policy")
        unless ($policy =~ /^stop:/);

    return $self->stop();
}

my %default_policies_message = (
    error_no_policy  =>
        "agent error: unknown status as no user event policy was computed",
    error_no_message =>
        "agent error: no user event message set by server",
    error_no_event   =>
        "agent error: no user event message set by agent",
    agent_failure    =>
        "agent error: got unexpected error while processing job usercheck",
    event_failure    =>
        "agent error: got unsupported event while processing user answer",

    # Default message if not set by server
    nouser           => "no active user",
);

sub status_for_server {
    my ($self) = @_;

    my $status = 'error_no_event';
    my $event  = $self->{_on_event} || 'on_none';
    my $policy = $self->{"_$event"};

    if (defined($policy)) {
        my @policies = split(':',$policy);
        $status = $policies[1] || 'error_no_policy' if (@policies > 1);
        $self->{_status}->{mesg} = $policies[2] if (@policies > 2);
    }

    $self->{_status}->{status} = $status;
    unless ($self->{_status}->{mesg}) {
        $self->{_status}->{mesg}= $default_policies_message{$status} ||
        $default_policies_message{'error_no_message'};
    }

    return $self->{_status};
}

sub info {
    my ($self, $message) = @_;

    my $header =
    $self->{logger}->info($self->tagged($message)) if $self->{logger};
}

sub error {
    my ($self, $message) = @_;

    # Eventually store erro event as this defines returned server status
    $self->{_on_event} = 'on_error'
        unless ($self->{_on_event});

    $self->{logger}->error($self->tagged($message)) if $self->{logger};

    return $self->stop();
}

sub continue {
    my ($self) = @_;

    $self->{_stopped} = 0 ;
}

sub stop {
    my ($self) = @_;

    $self->{_stopped} = 1 ;
}

sub stopped {
    my ($self, $param) = @_;

    if (defined($param)) {
        $self->{_stopped} = $param !~ /^0|no$/ ;
        $self->error($param) unless ($param =~ /^0|1|yes|no$/);

    } elsif ($self->{_stopped}) {
        if ($self->{on_timeout}) {
            $self->info("stopping current job on user interaction time-out");
        } else {
            $self->info("stopping current job by user choice");
        }

    } elsif ($self->{on_timeout}) {
        $self->info("current job continued on user interaction time-out");
    } else {
        $self->info("current job continued by user choice");
    }

    return $self->{_stopped};
}

# Methods to overload
sub tell_users {
    my ($self) = @_;

    $self->error("user interaction support failed");
}

1;
__END__

=head1 NAME

FusionInventory::Agent::Task::Deploy::UserCheck - Deploy task user checks

=head1 DESCRIPTION

This module provides object class to interact with logged users during
a deploy task.

It can be used for any job managed during one deploy task. It can be used
before the downloading step and/or after the actions processing. This
may give a chance for user to stop the current job or to be alerted of
done job.

The object is intended to show a modal windows or a notification to any
logged user.

=head1 OBJECTS STRUCTURE

While instanciated, the

=head1 Methods

=head2 PACKAGE->new(%params)

Returns a newly created FusionInventory::Agent::Task::Deploy::UserCheck
object.

Availables parameters:

=over

=item logger a logger object

=item check  a hash ref containing supported values to import

=back

Supported values for check hasf ref:

=over

=item title      Title to be used in a modal window

=item text       Text of the window or notification

=item icon       Icon to be used in window or notification

=item buttons    Buttons to expose to user. The button caption is static and
                 the used text should be coherent with buttons caption.

=item timeout    The time-out in second to wait for a user response

=item wait       Should we have to wait the user response

=item platform   Platform or  list of platforms on which we are expecting
                 user interaction. User interaction will be skipped if the
                 agent is not on any expected platform.

=item type       Type of user check to select when it should happen:
                   - "before": for checking user before downloading and
                               processing the deploy job
                   - "after" : for checking or notify the user after the
                               deploy job has been processed.

=back

Following values may to be used to define what should be done while buttons
are clicked or related event occurs:

=over

=item on_ok      To be done after user has clicked "OK" button.

=item on_cancel  To be done after user has clicked "Cancel" button.

=item on_yes     To be done after user has clicked "Yes" button.

=item on_no      To be done after user has clicked "No" button.

=item on_retry   To be done after user has clicked "Retry" button.

=item on_try     To be done after user has clicked "Try" button.

=item on_abort   To be done after user has clicked "Abort" button.

=item on_timeout To be done if user hasn't clicked any button and after
                 the defined time-out.

=item on_nouser  To be done if no user is logged

=back

Each event should be a string with the following format:
  "<local_policy>:<server_policy>:<message to send back>"

<local_policy> must be one of the following string:

=over

=item continue So the job processing will continue

=item stop     To stop the job processing

=back

<server_policy> should be a string send back to server as status.
<message to send back> should be a string send back to server as status message.

Remark: as semi-colon is used as delimiter, server should not use it in
sent policy.

=head2 $OBJ->tell_users()

Start the user interaction and wait until all expected events occurred.

Be careful, this may block the caller as long as the defined time-out,
and even more on server handling a lot of user sessions.

=head2 $OBJ->stopped($condition)

Without $condition, returns true if the user interaction matched and event
telling the current job has to be skipped while the user check is a 'before'
type check.

For 'after' type check, it has only the meaning to not process any following
'after' user check in a list context, until only one 'after' check is really
expected, this call could be avoided in that case.

If $condition is given, set _stopped private value accordingly:
 - 0 or 'no' : has the same effect than calling $OBJ->continue()
 - 1 or 'yes': defines the _stopped private value to be true.
 - any text: log the text as error and set _stopped private value to be true.

=head2 $OBJ->continue()
Set _stopped private value so calling stopped() method will return false.

=head2 $OBJ->stop()
Set _stopped private value so calling stopped() method will return true.
