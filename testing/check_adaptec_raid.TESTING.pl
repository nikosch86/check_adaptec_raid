#!/usr/bin/perl -w

use strict;
use warnings;
use Getopt::Long qw(:config no_ignore_case);

our $VERBOSITY = 0;
our $VERSION = '0.1';
our $NAME = "Thomas-Krenn Adaptec Raid Controller Nagios/Icinga Plugin";
our $EXITSTATUS = 0;
use constant {
	STATE_OK => 0,
	STATE_WARNING => 1,
	STATE_CRITICAL => 2,
	STATE_UNKNOWN => 3,
};

# Returns StatusCode 0,1,2,3
sub myStatus {
	my $prevStatus = $_[0];
	my $nextStatus = $_[1];
	my $returnStatus = STATE_OK;
	if ($prevStatus >= $nextStatus) {
		$returnStatus = $prevStatus;
	} else {
		$returnStatus = $nextStatus;
	}

	return $returnStatus;
}

# Explains the Usage of the plugin, also which options take which values
sub displayUsage {
	print "Usage: \n";
	print "  [ -C <Controller number> ] [ -LD <Logical device number> ]\n";
	print "  [ -PD <Physical device number> ] [ -T <Warning Temp., Crit. Temp.> ]\n";
	print "  [ -h | --help ]\n	Display this help page\n";
	print "  [ -v | -vv | -vvv | --verbose ]\n	Sets the verbosity level\n	no -v single line output for Nagios/Icinga\n	-v   single line with more details\n	-vv  multiline output for debugging errors and more detailed information\n	-vvv is for plugin problem diagnosis\n";
	print "  [ -V --version ]\n	Displays the Version of the tk-adaptec-plugin and the version of arcconf\n";
	print "  [ -C <Controller Number> | --controller <Controller Number> ]\n	Specifies a Controller number, (Default 1).\n";
	print "  [ -LD | --logicaldevice <Log. device number> ]\n	Specifies one or more Logical Devices to monitor.\n	Accepts a positive Integer or a comma seperated list as additional argument\n	(Default all)\n";
	print "  [ -PD | --physicaldevice <Phys. device number> ]\n	Specifies one or more Physical Devices to monitor.\n	Accepts a positive Integer or a comma seperated list as additional argument\n	(Default all)\n";
	print "  [ -Tw | --temperature-warn ]\n	Specifies the RAID-Controller temperature warning range, default is 50 C or more\n";
	print "  [ -Tc | --temperature-critical ]\n	Specifies the RAID-Controller temperature critical error range, default is 60 C or more\n";
	print "  [ -p <path> | --path <path>]\n	Specifies the path to arcconf.\n	Default is /usr/bin/arcconf  C:\\Programme\\Adaptec\\RemoteArcconf\\arcconf.exe\n";
	print "  [ -z <0/1> | ZMM <0/1> ]\n	Boolean Value which specifies if a Zero-Maintenance Module is available\n	(1 is available, 0 is not available). (Default 1)\n	This option is required if you have an Adaptec Raid Controller without a ZMM.\n\n";
}

# Displays a short Help text for the user
# TODO: ADD URL and Mailing List
sub displayHelp {
	print $NAME . " Version: " . $VERSION ."\n";
	print "Copyright (C) 2009-2013 Thomas-Krenn.AG\n";
	print "Current updates available via git at:\n  http://git.thomas-krenn.com/check_adaptec_raid.git\n";
	print "This Nagios/Icinga Plugin checks ADAPTEC RAID-Controllers for Controller, \nPhysical-Device and Logical Device warnings and errors. \n";
	print "In order for this plugin to work properly you need to add the \nnagios-user to your sudoers file (or create a new one in /etc/sudoers.d/).\n";
	print "This is required as arcconf must be called with sudo permissions.\n";
	displayUsage();
	print "Further information about this plugin can be found at:
  http://www.thomas-krenn.com/de/wiki/Adaptec_RAID_Monitoring_Plugin and
  http://www.thomas-krenn.com/de/wiki/Adaptec_RAID_Monitoring_Plugin
Please send an email to the tk-monitoring plugin-user mailing list:
  tk-monitoring-plugins-user\@lists.thomas-krenn.com
if you have questions regarding the use of this software, to submit patches, or
suggest improvements. The mailing list archive is available at:
  http://lists.thomas-krenn.com/pipermail/tk-monitoring-plugins-user\n";
	exit(STATE_UNKNOWN);
}

# Prints the Name, Version of the Plugin
# Also Prints the name, version of arcconf and the version of the RAID-Controller
sub displayVersion {
#	my $sudo = $_[0];
#	my $arcconf = $_[1];
#	my @arcconfVersion = `$sudo $arcconf`;
#	print $NAME . "\nVersion: ". $VERSION . "\n\n";
#	foreach my $line (@arcconfVersion){
#		if(index($line, "| UCLI |" ) ne "-1") {
#			$line =~ s/\s+\|.UCLI.\|\s+//g;
#			print $line. "";
#		}
#	}
	print "1.0";
}

# Implementation from check_LSI_raid
# Uses correct Nagios Threshold implementation
# Nagios development guidelines: temperature threshold sheme
# http://nagiosplug.sourceforge.net/developer-guidelines.html#THRESHOLDFORMAT
# Returns a temperature range (array) in or out which a temperature should be
# Array content: ("in" or "out", range from, range to)
# Example ranges:
#				Generate an alert if x...
#	-Tw 10			< 0 or > 10, (outside the range of {0 .. 10})
#	-Tw 10:			< 10, (outside {10 .. inf})
#	-Tw ~:10		> 10, (outside the range of {-inf .. 10})
#	-Tw 10:20		< 10 or > 20, (outside the range of {10 .. 20})
#	-Tw @10:20		>= 10 and <= 20, (inside the range of {10 .. 20})
sub getThresholds {
	my @thresholds = @{($_[0])};
	my $default = $_[1];

	if(scalar(@thresholds) eq 0) {
		return @thresholds = ("out", -273, $default);
	}
	if(substr($thresholds[0], 0, 1) eq "@") {
		if($thresholds[0] =~ /^\@([0-9]*)\:([0-9]*)$/) {
			@thresholds = ("in", $1, $2);
		} else {
			print "Invalid temperature parameter!";
			exit(STATE_UNKNOWN);
		}
	} elsif(substr($thresholds[0], 0, 1) eq "~") {
		if($thresholds[0] =~ /^\~\:([0-9]*)$/) {
			@thresholds = ("out", -273, $1);
		} else {
			print "Invalid temperature parameter!";
			exit(STATE_UNKNOWN);
		}
	} elsif(index($thresholds[0], ":") ne -1) {
		if($thresholds[0] =~ /^([0-9]*)\:([0-9]{1,3})$/) {
			@thresholds = ("out", $1, $2);
		} elsif($thresholds[0] =~ /^([0-9]*)\:$/) {
			@thresholds = ("in", -273, ($1 - 1));
		} else {
			print "Invalid temperature parameter!";
			exit(STATE_UNKNOWN);
		}
	} else {
		@thresholds = ("out", 0, $thresholds[0]);
	}
	if(($thresholds[1] =~ /^(-?[0-9]*)$/) && ($thresholds[2] =~ /^(-?[0-9]*)$/)) {
		return @thresholds;
	} else {
		print "Invalid temperature parameter!";
		exit(STATE_UNKNOWN);
	}
}


# Returns Information about the Adaptec RAID-Controller itsself:
#		- Controller Status
#		- Defunctional Disks
#		- Logical Devices which have failed/are degraded
#		- Temperature
# 		- Status of ZMM if present
sub getControllerCfg {
	my $sudo = $_[0];
	my $arcconf = $_[1];
	my $controller = $_[2];
	my @temperature_w = @{($_[3])};
	my @temperature_c = @{($_[4])};
	my $zmm = $_[5];
	my $status = 0; # Return Status
	my $statusMessage = ''; # Return String
	my @output = `/bin/cat /home/fnemeth/git/check_adaptec_raid/arcconf_output/controller_output`;
	my @linevalues;

	if(!defined($output[0]) || ($output[0] eq "Controllers found: 0\n") ||
	!defined($output[1]) || ($output[1] eq "Invalid controller number.\n")) {
		print "Invalid controller number or no controller found!\n";
		exit(STATE_UNKNOWN);
	}

	foreach my $line (@output) {
		if(index($line, ':') != -1) {
			@linevalues = split(/:/, $line);
			$linevalues[0] =~ s/^\s+|\s+$//g;
			$linevalues[1] =~ s/^\s+|\s+$//g;

			# Overall Controller Status
			if($linevalues[0] eq "Controller Status") {
				if ($linevalues[1] ne "Optimal") {
					$status = myStatus($status, STATE_CRITICAL);
					if ($VERBOSITY == 0) {$statusMessage .= "Ctrl. Status critical, "; }
					if ($VERBOSITY == 1) {$statusMessage .= "Controller Status is critical, "; }
					if ($VERBOSITY >= 2) {$statusMessage .= "The Controller Status is not running Optimal, "; }
				}
			}
			# Defunctional disks
			elsif($linevalues[0] eq "Defunct disk drive count") {
				if ($linevalues[1] ne "0") {
					$status = myStatus($status, STATE_CRITICAL);
					if ($VERBOSITY == 0) {$statusMessage .= "Defunct. disks, "; }
					if ($VERBOSITY >= 1) {$statusMessage .= $linevalues[1] . " disks are defunctional, "; }
				}
			}

			# Logical Devices total/failed/degraded
			# Warning since the raid is still recoverable, if it isnt you wont need a nagios plugin to notice that!
			elsif($linevalues[0] eq "Logical devices/Failed/Degraded") {
				$linevalues[1] =~ /([0-9]+)\/([0-9]+)\/([0-9]+)/;
				my $totalDisks = $1;
				my $totalFailed = $2;
				my $totalDegraded = $3;
				if ($totalFailed ne '0' || $totalDegraded ne '0') {
					$status = myStatus($status, STATE_WARNING);
					if ($VERBOSITY == 0) {$statusMessage .= "Log. device failed/degraded, "; }
					if ($VERBOSITY == 1) {$statusMessage .= "Logical devices have failed or are degraded, "; }
					if ($VERBOSITY == 2) {$statusMessage .= "Disks have failed or the Raid is degraded, "; }
					if ($VERBOSITY == 3) {$statusMessage .= "Disks have failed or the Raid is degraded: (Total Disks: ". $totalDisks . ", Failed: " . $totalFailed . ", Degraded: " . $totalDegraded . "), "; }
				}
			}

			# Warning if temperature is over the set Threshold
			elsif($linevalues[0] eq "Temperature") {
				my $crit = 0;
				my ($controllerTemp) = $linevalues[1] =~ /(^[0-9]+)/;
				if ($temperature_w[0] eq "in") {
					if (($controllerTemp >= $temperature_w[1]) && ($controllerTemp <= $temperature_w[2])) {
						if ($temperature_c[0] eq "in") {
							if (($controllerTemp >= $temperature_c[1]) && ($controllerTemp <= $temperature_c[2])) {
								$crit = 1;
								$status = myStatus($status, STATE_CRITICAL);
								if ($VERBOSITY == 0) {$statusMessage .= "Ctrl. temp. critical, "; }
								if ($VERBOSITY == 1) {$statusMessage .= "Temperature critical: " . $controllerTemp . " C, "; }
								if ($VERBOSITY == 2) {$statusMessage .= "Temperature critical: ". $controllerTemp . " C, "; }
								if ($VERBOSITY == 3) {$statusMessage .= "Temperature critical (Threshold: ".$temperature_c[1]." ,".$temperature_c[2]." C):".$controllerTemp." C, "; }
							}
						} else {
							if (($controllerTemp < $temperature_c[1]) || ($controllerTemp > $temperature_c[2])) {
								$crit = 1;
								$status = myStatus($status, STATE_CRITICAL);
								if ($VERBOSITY == 0) {$statusMessage .= "Ctrl. temp. critical, "; }
								if ($VERBOSITY == 1) {$statusMessage .= "Temperature critical: " . $controllerTemp . " C, "; }
								if ($VERBOSITY == 2) {$statusMessage .= "Temperature critical: ". $controllerTemp . " C, "; }
								if ($VERBOSITY == 3) {$statusMessage .= "Temperature critical (Threshold: ".$temperature_c[1].", ".$temperature_c[2]." C):".$controllerTemp." C, "; }
							}
						}
						if ($crit eq "0") {
							$status = myStatus($status, STATE_WARNING);
							if ($VERBOSITY == 0) {$statusMessage .= "Ctrl. temp. warning, "; }
							if ($VERBOSITY == 1) {$statusMessage .= "Temperature Warning: ".$controllerTemp." C, "; }
							if ($VERBOSITY == 2) {$statusMessage .= "Temperature Warning (Threshold: ".$temperature_w[1].", ".$temperature_w[2]." C): ".$controllerTemp." C,"; }
							if ($VERBOSITY == 3) {$statusMessage .= "Temperature Warning (Threshold: ".$temperature_w[1].", ".$temperature_w[2].", Critical Threshold: ".$temperature_c[1].", ".$temperature_c[2]." C):".$controllerTemp." C, "; }
						}
					}
				} else {
					if (($controllerTemp < $temperature_w[1]) || ($controllerTemp > $temperature_w[2])) {
						if ($temperature_c[0] eq "in") {
							if (($controllerTemp >= $temperature_c[1]) && ($controllerTemp <= $temperature_c[2])) {
								$crit = 1;
								$status = myStatus($status, STATE_CRITICAL);
								if ($VERBOSITY == 0) {$statusMessage .= "Ctrl. temp. critical, "; }
								if ($VERBOSITY == 1) {$statusMessage .= "Temperature critical: " . $controllerTemp . " C, "; }
								if ($VERBOSITY == 2) {$statusMessage .= "Temperature critical: ". $controllerTemp . " C, "; }
								if ($VERBOSITY == 3) {$statusMessage .= "Temperature critical (Threshold: ". $temperature_c[1]. ", ". $temperature_c[2] . " C):" . $controllerTemp . " C, "; }
							}
						} else {
							if (($controllerTemp < $temperature_c[1]) || ($controllerTemp > $temperature_c[2])) {
								$crit = 1;
								$status = myStatus($status, STATE_CRITICAL);
								if ($VERBOSITY == 0) {$statusMessage .= "Ctrl. temp. critical, "; }
								if ($VERBOSITY == 1) {$statusMessage .= "Temperature critical: " . $controllerTemp . " C, "; }
								if ($VERBOSITY == 2) {$statusMessage .= "Temperature critical: ". $controllerTemp . " C, "; }
								if ($VERBOSITY == 3) {$statusMessage .= "Temperature critical (Threshold: ". $temperature_c[1]. ", ". $temperature_c[2] . " C):" . $controllerTemp . " C, "; }
							}
						}
						if ($crit eq "0") {
							$status = myStatus($status, STATE_WARNING);
							if ($VERBOSITY == 0) {$statusMessage .= "Ctrl. temp. warning, "; }
							if ($VERBOSITY == 1) {$statusMessage .= "Temperature Warning: " . $controllerTemp . " C, "; }
							if ($VERBOSITY == 2) {$statusMessage .= "Temperature Warning (Threshold: ". $temperature_w[1] . ", " . $temperature_w[2]. " C): " . $controllerTemp . " C,"; }
							if ($VERBOSITY == 3) {$statusMessage .= "Temperature Warning (Threshold: ". $temperature_w[1] . ", " . $temperature_w[2]. ", Critical Threshold: ". $temperature_c[1] . ", " . $temperature_c[2] ." C):" . $controllerTemp . " C, "; }
						}
					}
				}
			}

			# Zero Maintenance Module
			elsif($linevalues[0] eq "Status") {
				if ( $zmm == 1) {
					if ($linevalues[1] ne "ZMM Optimal") {
						$status = myStatus($status, STATE_CRITICAL);
						if ($VERBOSITY == 0) {$statusMessage .= "ZMM critical, "; }
						if ($VERBOSITY == 1) {$statusMessage .= "ZMM Module state critical, "; }
						if ($VERBOSITY >= 2) {$statusMessage .= "Zero Maintenance Module error or module not found!, "; }
					}
				}
			}
		}

	}
	return ($status, $statusMessage);
}

# Returns Information about physical Devices attached to the Adaptec Raid-Controller:
#		- Disk Status
#		- S.M.A.R.T. Status
#		- S.M.A.R.T. Warnings
#		- Low-RPM Warnings
#		- Failed Disk Segments
sub getPhysDevCfg {
	my $sudo = $_[0];
	my $arcconf = $_[1];
	my $controller = $_[2];
	my $devices = $_[3];
	my $devicenum = -1;
	my $statusMessage = ''; # Return String
	my @output = `/bin/cat /home/fnemeth/git/check_adaptec_raid/arcconf_output/physical_enclosure_output`;
	my (@faildevices, @linevalues, @devicelist);
	my ($status, $found, $count) = 0; # Return Code, true/false if users devices are found
	my $i = 0; # helper for arrays
	my @userdevicelist;
	
	foreach my $line (@output) {
		if ($line =~ /Device #([0-9]+)/) {
			# vorher +=
			$devicelist[$i] = $1;
			$i++;
		}
	}
	$i = 0;
	
	# Split up the ',' seperated list
	if (defined($devices)) { 
		@userdevicelist = split(',', $devices);
		$count = scalar(@userdevicelist); 
		foreach my $device (@devicelist) {
			foreach my $userdevice (@userdevicelist) {
				if ($device == $userdevice) { 
					$devicenum = $device; 
					$found += 1;
				}
			}
		}
	} else {
		$count = 1;
		$found = 1;
	}
	
	foreach my $line (@output) {
		# If users choice could not be found, dont even try
		if ( $found != $count ) {
			$devicenum = -1; 
		}
		if($line =~ /(Device #)([0-9]+)/) {
			if(!defined($userdevicelist[0])) {
				$devicenum = $2;
			} else {
				if ( $i < $count) {
					$devicenum = $userdevicelist[$i];
					$i++;
				}
			}
		}

		# Check if Disk is a Backplane 
		if($line =~ /Device is an Enclosure services device/) {
			$devicenum = -2;
		}
		# Linesplitting and removing spaces
		if($devicenum ne -2 && $devicenum ne -1 && index($line, ':') != -1) {
			@linevalues = split(/:/, $line);
			$linevalues[0] =~ s/^\s+|\s+$//g;
			$linevalues[1] =~ s/^\s+|\s+$//g;

			# Main disk status (Online/Offline?)
			if($linevalues[0] eq "State") {
				if ($linevalues[1] ne "Online" &&
					$linevalues[1] ne "Hot Spare" &&
					$linevalues[1] ne "Ready" &&
					$linevalues[1] ne "Online (JBOD)") {
						#check if device is in failed array, else add it
						if(!grep {$_ eq $devicenum} @faildevices) {
							push(@faildevices, $devicenum);
						}
						$status = myStatus($status, STATE_CRITICAL);
						if ($VERBOSITY == 0) {$statusMessage .= "Disk offline, "; }
						if ($VERBOSITY >= 1) {$statusMessage .= "Disk $devicenum is offline, "; }
				}
			}
			
			# Overall S.M.A.R.T. status
			elsif($linevalues[0] eq "S.M.A.R.T.") {
				if ($linevalues[1] ne "No") {
					if (!grep {$_ eq $devicenum} @faildevices) {
						push(@faildevices, $devicenum);
					}
					$status = myStatus($status, STATE_CRITICAL);
					if ($VERBOSITY == 0) {$statusMessage .= "S.M.A.R.T. critical, "; }
					if ($VERBOSITY >= 1) {$statusMessage .= "Disk $devicenum: S.M.A.R.T. status critical, "; }
				}
			}

			# Check if any S.M.A.R.T. warnings occured
			elsif($linevalues[0] eq "S.M.A.R.T. warnings") {
				if ($linevalues[1] ne "0") {
					if (!grep {$_ eq $devicenum} @faildevices) {
						push(@faildevices, $devicenum);
					}
					$status = myStatus($status, STATE_WARNING);
					if ($VERBOSITY == 0) {$statusMessage .= "S.M.A.R.T. warning, "; }
					if ($VERBOSITY == 1) {$statusMessage .= "Disk $devicenum: S.M.A.R.T. warnings, "; }
					if ($VERBOSITY >= 2) {$statusMessage .= "Disk $devicenum: \nDisk has one or more S.M.A.R.T. warnings, "; }
				}
			}

			# Check if the disk does not run with full (physical) speed
			elsif($linevalues[0] eq "Power state") {
				if ($linevalues[1] ne "Full rpm") {
					if (!grep {$_ eq $devicenum} @faildevices) {
						push(@faildevices, $devicenum);
					}
					$status = myStatus($status, STATE_CRITICAL);
					if ($VERBOSITY == 0) {$statusMessage .= "Low rpm warning, "; }
					if ($VERBOSITY == 1) {$statusMessage .= "Disk $devicenum does not run with full speed, "; }
					if ($VERBOSITY >= 2) {$statusMessage .= "Disk $devicenum: \nDisk run in a different power state (not full rpm), "; }
				}
			}

			# Look for bad device segments
			elsif($linevalues[0] eq "Failed logical device segments") {
				if ($linevalues[1] eq "True") {
					if (!grep {$_ eq $devicenum} @faildevices) {
						push(@faildevices, $devicenum);
					}
					$status = myStatus($status, STATE_CRITICAL);
					if ($VERBOSITY == 0) {$statusMessage .= "Log. device failed segm, "; }
					if ($VERBOSITY >= 1) {$statusMessage .= "Disk $devicenum has failed logical device segments, "; }
				}
			}
		}
	}

	# Invalid Physical Device Error
	if ( $devicenum eq -1 ) {
		print "Invalid Physical Device!\n";
		exit(STATE_UNKNOWN);
	}

	# Status output
	my $faildevicenum = scalar(@faildevices);
	if ($VERBOSITY >= 0 && $faildevicenum > 0) {
		$statusMessage .= "$faildevicenum phys. disk(s) failed, ";
	}

	return ($status, $statusMessage);
}

# Returns Information about logical Devices:
#		- General Logical Devices Status
#		- Failed Stripes
sub getLogDevCfg {
	my $sudo = $_[0];
	my $arcconf = $_[1];
	my $controller = $_[2];
	my $devices = $_[3];
	my $devicenum = -1;
	my $status = 0; #Return status
	my $statusMessage = ''; #Return string
	my @faildevices;
	my @output = `/bin/cat /home/fnemeth/git/check_adaptec_raid/arcconf_output/logical_all_output`;
	my @linevalues;
	my $i = 0;
	my $count = 0;
	my $found = 0;
	my @loglist;
	my @userloglist;

	foreach my $line (@output) {
		if($line =~ /(Logical device number )([0-9]+)/) {
		$loglist[$i] = $2;
		$i++;
		}
		
	} 
	$i = 0;

	if (defined($devices)) {
		@userloglist = split(',', $devices);
		$count = scalar(@userloglist);
		foreach my $logdev (@loglist) {
			foreach my $userlogdev (@userloglist) {
				if ($logdev == $userlogdev) {
					$devicenum = $logdev;
					$found += 1;
				}
			}
		}
	} else {
		$count = 1;
		$found = 1;
	}

	foreach my $line (@output) {
		if ($found != $count) {
			$devicenum = -1;
		}
		if($line =~ /Logical device number ([0-9]+)/) {
			if (!defined($userloglist[0])) {
				$devicenum = $1;
			} else {
				if ( $i < $count) {
					$devicenum = $userloglist[$i];
					$i++;
				}
			}
		}
		if($devicenum ne -1 && index($line, ':') != -1) {
			@linevalues = split(/:/, $line);
			$linevalues[0] =~ s/^\s+|\s+$//g;
			$linevalues[1] =~ s/^\s+|\s+$//g;

			# Main logical device status
			if($linevalues[0] eq "Status of logical device") {
				if ($linevalues[1] ne "Optimal") {
					if (!grep {$_ eq $devicenum} @faildevices) {
						push(@faildevices, $devicenum);
					}
						$status = myStatus($status, STATE_CRITICAL);
						if ($VERBOSITY == 0) {$statusMessage .= "Log. device critical, "; }
						if ($VERBOSITY >= 1) {$statusMessage .= "State of logical disk $devicenum critical, "; }
				}
			}
			# Check for failed stripes
			elsif($linevalues[0] eq "Failed stripes") {
				if ($linevalues[1] ne "No") {
					if (!grep {$_ eq $devicenum} @faildevices) {
						push(@faildevices, $devicenum);
					}
					$status = myStatus($status, STATE_CRITICAL);
					if ($VERBOSITY == 0) {$statusMessage .= "Failed stripes, "; }
						if ($VERBOSITY >= 1) {$statusMessage .= "Logical disk $devicenum has failed stripes, "; }
				}
			}
		}
	}

	# Invalid Logical Device Error
	if ( $devicenum eq -1 ) {
		print "Invalid Logical Device!\n";
		exit(STATE_UNKNOWN);
	}

	# Status Output
	my $faildevicenum = scalar(@faildevices);
	if ($VERBOSITY eq 0 && $faildevicenum > 0) {
		$statusMessage .= "$faildevicenum log. device(s) failed, ";
	}
	return ($status, $statusMessage);
}

MAIN: {
	my $controller = 1;
	my $logDevices;
	my $physDevices;
	my $sudo;
	my $arcconf;
	my $platform = $^O;
	my @temperature_w;
	my @temperature_c;
	my $zmm = 1;
	my $statusMessage; # printed status message

	if ( !(GetOptions(
		'v|verbose' => sub { $VERBOSITY = 1 },
		'vv' => sub { $VERBOSITY = 2 },
		'vvv' => sub { $VERBOSITY = 3 },
		'h|help' => sub {displayHelp();},
		'V|version' => sub {displayVersion($sudo, $arcconf);},
		'C|controller=i' => \$controller,
		'LD|logicaldevice=s' => \$logDevices,
		'PD|physicaldevice=s' => \$physDevices,
		'Tw|temperature-warn=s' => \@temperature_w,
		'Tc|temperature-crit=s' => \@temperature_c,
		'p|path=s' => \$arcconf,
		'z|ZMM=i' => \$zmm
	)))	{
		print $NAME . " Version: " . $VERSION ."\n";
		displayUsage();
		exit(STATE_UNKNOWN);
	}

	@temperature_w = getThresholds(\@temperature_w, 50);
	@temperature_c = getThresholds(\@temperature_c, 60);

	# Check platform
	if ($platform eq 'linux') {
		$sudo = '/usr/bin/sudo';
		if (!$arcconf) {
			$arcconf = '/usr/bin/arcconf';
		}
		unless ( -e $arcconf && -x $sudo ) {
			print "Permission denied or file not found!\n";
			exit(STATE_UNKNOWN);
		}
	} else {
		$sudo = '';
		if (!$arcconf) {
			$arcconf = 'C:\Programme\Adaptec\RemoteArcconf\arcconf.exe';
		}
		unless ( -e $arcconf ) { print "Executable not found!\n"; exit(STATE_UNKNOWN); }
	}

	# Input validation
	#my @controllerVersion = `$sudo $arcconf GETVERSION $controller`;
	#if($controllerVersion[1] eq "Invalid controller number.") {
	#	print "Invalid controller number, device not found!";
	#	exit(STATE_UNKNOWN);
	#}
	if($zmm != 1 && $zmm != 0) {
		print "Invalid ZMM parameter, must be 0 or 1!";
		exit(STATE_UNKNOWN);
	}

	# Set exit status
	my $newExitStatus = 0;
	my $newStatusMessage = '';
	($newExitStatus, $statusMessage) = getControllerCfg($sudo, $arcconf, $controller, \@temperature_w, \@temperature_c, $zmm);
	$newStatusMessage .= $statusMessage;
	$EXITSTATUS = myStatus($newExitStatus, $EXITSTATUS);
#	($newExitStatus, $statusMessage) = getPhysDevCfg($sudo, $arcconf, $controller, \@physDevices);
	($newExitStatus, $statusMessage) = getPhysDevCfg($sudo, $arcconf, $controller, $physDevices);
	$newStatusMessage .= $statusMessage;
	$EXITSTATUS = myStatus($newExitStatus, $EXITSTATUS);
#	($newExitStatus, $statusMessage) = getLogDevCfg($sudo, $arcconf, $controller, \@logDevices);
	($newExitStatus, $statusMessage) = getLogDevCfg($sudo, $arcconf, $controller, $logDevices);
	$newStatusMessage .= $statusMessage;
	$EXITSTATUS = myStatus($newExitStatus, $EXITSTATUS);
	if($EXITSTATUS == 0) { print "AACRAID OK (Ctrl #$controller)\n"; }
	elsif($EXITSTATUS == 1) { if($VERBOSITY eq 0) { chop($newStatusMessage); chop($newStatusMessage); } print "AACRAID WARNING (Ctrl #$controller): [$newStatusMessage]\n"; }
	elsif($EXITSTATUS ==2) { if($VERBOSITY eq 0) { chop($newStatusMessage); chop($newStatusMessage); } print "AACRAID CRITICAL (Ctrl #$controller): [$newStatusMessage]\n"; }
	exit($EXITSTATUS);
}