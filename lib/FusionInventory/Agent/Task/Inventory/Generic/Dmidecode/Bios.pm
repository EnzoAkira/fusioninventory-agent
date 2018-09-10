package FusionInventory::Agent::Task::Inventory::Generic::Dmidecode::Bios;

use strict;
use warnings;
#use Switch;

use parent 'FusionInventory::Agent::Task::Inventory::Module';

use FusionInventory::Agent::Tools;
use FusionInventory::Agent::Tools::Generic;

sub isEnabled {
    return 1;
}

sub doInventory {
    my (%params) = @_;

    my $inventory = $params{inventory};
    my $logger    = $params{logger};

    my ($bios, $hardware) = _getBiosHardware(logger => $logger);

    $inventory->setBios($bios) if $bios;
    $inventory->setHardware($hardware) if $hardware;
}

sub _getBiosHardware {
    my $infos = getDmidecodeInfos(@_);

    my $bios_info    = $infos->{0}->[0];
    my $system_info  = $infos->{1}->[0];
    my $base_info    = $infos->{2}->[0];
    my $chassis_info = $infos->{3}->[0];

    
    # For testing
    
    #my @infozero = $infos->{0}->[0];
    #my @infoone = $infos->{1}->[0];
    #my @infotwo = $infos->{2}->[0];
    #my @infothree = $infos->{3}->[0];
    
    
    my @bios_info       = $bios_info;
    my @system_info     = $system_info;
    my @base_info       = $base_info;
    my @chassis_info    = $chassis_info;
    
    print Data::Dumper->Dump([\@bios_info], [qw(bios_info)]);
    print Data::Dumper->Dump([\@system_info], [qw(system_info)]);
    print Data::Dumper->Dump([\@base_info], [qw(base_info)]);
    print Data::Dumper->Dump([\@chassis_info], [qw(chassis_info)]);
    
    for my $href ( @bios_info ){
        foreach my $rolev (values %$href ){
            if (!$rolev || $rolev eq ''){
                $rolev = 'N/A';
            }
        }
        $bios_info = $href;
    }
    
    for my $href ( @system_info ){
        for my $rolev (values %$href ){
            if (!$rolev || $rolev eq ''){
                $rolev = 'N/A';
            }
        }
        $system_info = $href;
    }
    
    for my $href ( @base_info ){
        for my $rolev (values %$href ){
            if (!$rolev || $rolev eq ''){
                $rolev = 'N/A';
            }
        }
        $base_info = $href;
    }
    
    for my $href ( @chassis_info ){
        for my $rolev (values %$href ){
            if (!$rolev || $rolev eq ''){
                $rolev = 'N/A';
            }
        }
        $chassis_info = $href;
    }
     
    # End Testing
    
    my $bios = {
        BMANUFACTURER => '',
        BDATE         => '',
        BVERSION      => '',
        ASSETTAG      => '',
        SMODEL        => '',
        MMODEL        => '',
        SKUNUMBER     => '',
        SMANUFACTURER => '',
        MMANUFACTURER => '',
        SSN           => '',
        MSN           => ''
    };
    
    for my $href ( @chassis_info ){
            foreach my $role (keys %$href ){
                if ($role eq 'Asset Tag') {
                    $bios->{ASSETTAG} = $href->{$role};
                }
            }
            
        if ($bios->{ASSETTAG} eq ''){
            $bios->{ASSETTAG} = 'N/A';
        }
    }
    
    for my $href ( @bios_info ){
        foreach my $role (keys %$href ){
                
                if ($role eq 'Vendor'){
                    $bios->{BMANUFACTURER} = $href->{$role}
                }
                if ($role eq 'Release Date'){
                     $bios->{BDATE} = $href->{$role}
                }
                if ($role eq 'Version'){
                    $bios->{BVERSION} = $href->{$role}
                }
            }
            #switch ($role) {
            #   case "Vendor"            { $bios->{BMANUFACTURER} = $href->{$role}}
            #   case "Release Date"      { $bios->{BDATE} = $href->{$role}}
            #   case "Version"           { $bios->{BVERSION} = $href->{$role}}
            #}
        if ($bios->{BMANUFACTURER} eq ''){
            $bios->{BMANUFACTURER} = 'N/A';
        }
        if ($bios->{BDATE} eq ''){
            $bios->{BDATE} = 'N/A';
        }
        if ($bios->{BVERSION} eq ''){
            $bios->{BVERSION} = 'N/A';
        }
    }
    
    # Fix issue #311: system_info 'Version' is a better 'Product Name' for Lenovo systems
    if ($system_info->{'Version'} &&
        $system_info->{'Manufacturer'} &&
        $system_info->{'Manufacturer'} =~ /^LENOVO$/i &&
        $system_info->{'Version'} =~ /^(Think|Idea|Yoga|Netfinity|Netvista|Intelli)/i) {
            my $product_name                = $system_info->{'Version'};
            $system_info->{'Version'}       = $system_info->{'Product Name'};
            $system_info->{'Product Name'}  = $product_name;
    }
    
    for my $href ( @system_info ){
        foreach my $role (keys %$href ){
            if ($role eq 'Product'){
                $bios->{SMODEL} = $href->{$role};
            }
            if ($role eq 'Product Name'){
                $bios->{SMODEL} = $href->{$role};
            }
            if ($role eq 'SKU Number'){
                $bios->{SKUNUMBER} = $href->{$role};
            }
            if ($role eq 'Manufacturer'){
                $bios->{SMANUFACTURER} = $href->{$role};
            }
            if ($role eq 'Vendor'){
                $bios->{SMANUFACTURER} = $href->{$role};
            }
            if ($role eq 'Serial Number'){
                $bios->{SSN} = $href->{$role};
            }
        }
        if ($system_info->{'UUID'} ne ''){
            if ($bios->{SSN} eq '' || $bios->{SSN} eq '0' || $bios->{SSN} eq 'N/A' ){
            $bios->{SSN} = $system_info->{'UUID'};
            }
        }
        if ($bios->{SKUNUMBER} eq '' || $bios->{SKUNUMBER} eq '0'){
            $bios->{SKUNUMBER} = 'N/D';
        }
    }
    
    for my $href ( @base_info ){
        foreach my $role (keys %$href ){
            if ($role eq 'Product Name'){
                $bios->{MMODEL} = $href->{$role};
            }
            if ($role eq 'Serial Number'){
                $bios->{MSN} = $href->{$role};
            }
            if ($role eq 'Manufacturer'){
                $bios->{MMANUFACTURER} = $href->{$role};
            }
        }
        
        if ($bios->{MSN} eq '' || $bios->{MSN} eq '0'){
            $bios->{MSN} = 'N/A';
        }
        if ($bios->{MMODEL} eq '' || !defined $bios->{MMODEL}){
            $bios->{MMODEL} = 'N/D';
        }
        if ($bios->{MMANUFACTURER} eq '' || !defined $bios->{MMANUFACTURER}){
            $bios->{MMANUFACTURER} = 'N/D';
        }
    }
    
    if ($bios->{MMODEL} && $bios->{MMODEL} eq "VirtualBox"){
        $bios->{SSN} = $system_info->{'UUID'};
    }
    
    #my $bios = {
    #    BMANUFACTURER => $bios_info->{'Vendor'},
    #    BDATE         => $bios_info->{'Release Date'},
    #    BVERSION      => $bios_info->{'Version'},
    #    ASSETTAG      => $chassis_info->{'Asset Tag'}
    #};  
    
    #$bios->{MMODEL} = $base_info->{'Product Name'};
    #$bios->{MMANUFACTURER} = $base_info->{'Manufacturer'};
    #$bios->{MSN} = $base_info->{'Serial Number'};
       
       
    my $hardware = {
        UUID => $system_info->{'UUID'},
        CHASSIS_TYPE  => $chassis_info->{'Type'}
    };

    return $bios, $hardware;
}

1;
