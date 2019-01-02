####################################################################
#
# ECDefectTracking::CQ::Driver  Object to represent interactions with 
#        ClearQuest.
#
####################################################################
package ECDefectTracking::CQ::Driver;
@ISA = (ECDefectTracking::Base::Driver);
use ElectricCommander;
use Time::Local;
use File::Basename;
use File::Copy;
use File::Path;
use File::Spec;
use File::stat;
use File::Temp;
use FindBin;
use Sys::Hostname;

#use CQPerlExt;


if (!defined ECDefectTracking::Base::Driver) {
    require ECDefectTracking::Base::Driver;
}

if (!defined ECDefectTracking::CQ::Cfg) {
    require ECDefectTracking::CQ::Cfg;
}

#-------------------------------------------------------------------------------
# Some useful constants for the benefit of the CQ API
#-------------------------------------------------------------------------------
$AD_PRIVATE_SESSION = 2;	# Only one client can access this session's data

$|=1;

####################################################################
# Object constructor for ECDefectTracking::CQ::Driver
#
# Inputs
#    cmdr          previously initialized ElectricCommander handle
#    name          name of this configuration
#                 
####################################################################
sub new {
    my $this = shift;
    my $class = ref($this) || $this;

    my $cmdr = shift;
    my $name = shift;

    my $cfg = new ECDefectTracking::CQ::Cfg($cmdr, "$name");
    if ("$name" ne "") {
        my $sys = $cfg->getDefectTrackingPluginName();
        if ("$sys" ne "EC-DefectTracking-CQ") { die "DefectTracking config $name is not type ECDefectTracking-CQ"; }
    }

    my ($self) = new ECDefectTracking::Base::Driver($cmdr,$cfg);

    bless ($self, $class);
    return $self;
}

####################################################################
# isImplemented
####################################################################
sub isImplemented {
    my ($self, $method) = @_;
    
    if ($method eq 'linkDefects' || 
        $method eq 'updateDefects' ||
        $method eq 'fileDefect' ||
        $method eq 'createDefects') {
    	return 1;
    } else {
        return 0;
    }
}

####################################################################
# linkDefects
#  
# Side Effects:
#   
# Arguments:
#   self -              the object reference
#   opts -              hash of options
#
# Returns:
#   Nothing
#
####################################################################
sub linkDefects {
    my ($self, $opts) = @_;
    
    # get back a hash ref
    my $defectIDs_ref = $self->extractDefectIDsFromProperty($opts->{propertyToParse}, $opts->{prefix});

    if (! keys % {$defectIDs_ref}) {
	print "No defect IDs found, returning\n";
	return;
    } 

    $self->populatePropertySheetWithDefectIDs($defectIDs_ref);

    my $defectLinks_ref = {}; # ref to empty hash
    
    my $cqSession = $self->getCQInstance();

    if (!$cqSession) {
	exit 1;
    }

    foreach my $e (keys % {$defectIDs_ref}) {             
        my ($name, $url) = $self->queryDefectSystemWithDefectID($e, $cqSession);
        
        print "Key: $e Name: $name\n";
        
		if ($name && $name ne "" && $url && $url ne "") {
		    $defectLinks_ref->{$name} = $url; 
		}
    }

    if (keys % {$defectLinks_ref}) {
		$self->populatePropertySheetWithDefectLinks($defectLinks_ref);
		$self->createLinkToDefectReport("ClearQuest Report");
    }
}

####################################################################
# updateDefects
#  
# Side Effects:
#   
# Arguments:
#   self -              the object reference
#   opts -              hash of options
#
# Returns:
#   Nothing
#
####################################################################
sub updateDefects {
    my ($self, $opts) = @_;
    # Attempt to read the property "/myJob/defectsToUpdate" 
    # or the property entered as the "property" parameter to the subprocedure   
    my $property = $opts->{property};    
    if (!$property || $property eq "") {
		print "Error: Property does not exist or is empty\n";
		exit 1;
    }
    my ($success, $xpath, $msg) = $self->InvokeCommander({SupressLog=>1,IgnoreError=>1}, "getProperty", "$property");
	if ($success) {
	    my $value = $xpath->findvalue('//value')->string_value;
	    $property = $value;
	} else {
	    # log the error code and msg
	    print "Error querying for $property as a property\n";
	    exit 1;
	}
    # split using ',' to get a list of key=value pairs
    print "Property : $property\n";
    my @pairs = split(',', $property);
    
    my $errors;
    my $updateddefectLinks_ref = {}; # ref to empty hash    
    
    my $cqSession = $self->getCQInstance();

    if (!$cqSession) {
        exit 1;
    }
    
    foreach my $val (@pairs) {
    	print "Current Pair: $val\n";
    	my @iDAndValue = split('=', $val);
    	# the key of each pair is the defect ID, 
    	# e.g. "NMB-11111" is the first key in the example above
    	my $idDefect = $iDAndValue[0];
    	# the value of each pair is the status,
    	# e.g. "Resolved", is the first value in the example above
    	my $valueDefect = $iDAndValue[1]; 
    	#Validate $idDefect $valueDefect
    	print "Current idDefect: $idDefect\n";
    	print "Current valueDefect: $valueDefect\n";
    	if (!$idDefect || $idDefect eq "" || !$valueDefect || $valueDefect eq "" ) {
			print "Error: Property format error\n";
			#return;
    	}else{
    		# Call function to resolve Defect	    	
		    my $message = "";	    
		    eval{
		        my $issue = $cqSession->GetEntity("defect", $idDefect);
				print "Issue: $issue \n";
		        $cqSession->EditEntity($issue,$valueDefect);		        

		        #if status = resolve The field "Resolution" is mandatory
		        if($valueDefect eq "Resolve" 
		              || $valueDefect eq "resolve"
		              || $valueDefect eq "Close"
		              || $valueDefect eq "close"){
		            $issue->SetFieldValue("Resolution", "Fixed");					
					$issue->SetFieldValue("Priority", "3-Normal Queue");
					$issue->SetFieldValue("Owner", $self->getConfigUser());
		        } 
		        
		        $status = $issue->Validate();
		        if ($status) {		            
		            $issue->Revert();
		            $message = "Error: failed trying to udpate $idDefect to $valueDefect status, with status: $status \n";
		            print "$message \n";
		            $updateddefectLinks_ref->{substr($message,0,250)} = "#";
                    $errors = 1;		            
		        }else { 
		            $issue->Commit();		               
                    $message = "$idDefect was successfully updated to $valueDefect status\n";
                    print "$message \n";
                    my ($name, $url) = $self->queryDefectSystemWithDefectIDUpdated($idDefect, $cqSession, $message);
                    if ($name && $name ne "" && $url && $url ne "") {
                        $updateddefectLinks_ref->{$name} = $url; 
                    }
		        }				
		    };
		    if ($@) {
		    	$message = "Error: failed trying to udpate $idDefect to $valueDefect status, with error: $@ \n";
		    	$updateddefectLinks_ref->{substr($message,0,250)} = "#";
		    	print "$message \n";
		    	$errors = 1;
		    };
    	}    	 
  	}
  	if (keys % {$updateddefectLinks_ref}) {
  		$propertyName_ref = "updatedDefectLinks"; 
		$self->populatePropertySheetWithDefectLinks($updateddefectLinks_ref, $propertyName_ref);
		$self->createLinkToDefectReport("ClearQuest Report");
    }
  	if($errors && $errors ne ""){
    	print "Defects update completed with some Errors\n"
    }
}

####################################################################
# createDefects
#  
# Side Effects:
#   
# Arguments:
#   self -              the object reference
#   opts -              hash of options
#
# Returns:
#   Nothing
#
####################################################################
sub createDefects {
    my ($self, $opts) = @_;
    
	my ($success, $xpath, $msg) = $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1},
			 "setProperty", "/myJob/config", "$opts->{config}");
	 
    my $mode = $opts->{mode};    
    if (!$mode || $mode eq "") {
		print "Error: mode does not exist or is empty\n";
		exit 1;
    }
    
    ($success, $xpath, $msg) = $self->InvokeCommander({SupressLog=>1,IgnoreError=>1}, "getProperties", {recurse => "0", path => "/myJob/ecTestFailures"});
    if (!$success) {
    	print "No Errors, so no Defects to create\n";
    	return 0;    	
    }    
    
    my $results = $xpath->find('//property');    
	if (!$results->isa('XML::XPath::NodeSet')) {
        # didn't get a nodeset
	    print "Didn't get a NodeSet when querying for property: ecTestFailures \n";
	    return 0;   
	}

    my $cqSession = $self->getCQInstance();
    if (!$cqSession) {
        exit 1;
    }
    
	my @propsNames = ();
	
	foreach my $context ($results->get_nodelist) {
		my $propertyName = $xpath->find('./propertyName', $context);
		push(@propsNames,$propertyName);    
	}
	
	my $createdDefectLinks_ref = {}; # ref to empty hash
	my $errors;
	
	foreach my $prop (@propsNames) {
		print "Trying to get Property /myJob/ecTestFailures/$prop \n";
		my ($jSuccess, $jXpath, $jMsg) = $self->InvokeCommander({SupressLog=>1,IgnoreError=>1}, "getProperties", {recurse => "0", path => "/myJob/ecTestFailures/$prop"});
		
		my %testFailureProps = {}; # ref to empty hash
		
		##Properties##
		#stepID
		my $stepID = "N/A";		
		#testSuiteName
		my $testSuiteName = "N/A";
		#testCaseResult
		my $testCaseResult = "N/A";
		#testCaseName
		my $testCaseName = "N/A";
		#logs
		my $logs = "N/A";
		#stepName
		my $stepName = "N/A";
		
		my $jResults = $jXpath->find('//property');
		foreach my $jContext ($jResults->get_nodelist) {			
			my $subPropertyName = $jXpath->find('./propertyName', $jContext)->string_value;
			my $value = $jXpath->find('./value', $jContext)->string_value;
			
			if ($subPropertyName eq "stepId"){$stepID = $value;}			
			if ($subPropertyName eq "testSuiteName"){$testSuiteName = $value;}
			if ($subPropertyName eq "testCaseResult"){$testCaseResult = $value;}
			if ($subPropertyName eq "testCaseName"){$testCaseName = $value;}
			if ($subPropertyName eq "logs"){$logs = $value;}
			if ($subPropertyName eq "stepName"){$stepName = $value;}				
		}
		
		my $message = "";		
		my $comment = "Step ID: $stepID "
					. "Step Name: $stepName "
					. "Test Case Name: $testCaseName ";
						
		if($mode eq "automatic"){
			eval{			    
			    $issue = $cqSession->BuildEntity("defect");
			    #$cqSession->EditEntity($issue, "modify");
			    			    
			    #Shoud set headline, severity = 3 (Average), description
			    $issue->SetFieldValue("Headline", "Defect: $prop");
			    $issue->SetFieldValue("Severity", "3-Average");
			    $issue->SetFieldValue("Description", "$comment");
			    
			    $status = $issue->Validate();
                if ($status) {                  
                    $issue->Revert();
                    $message = "Error: failed trying to create defect, with error: $status \n";
                    print "$message \n";
                    $createdDefectLinks_ref->{"$comment"} = "$message?prop=$prop";#?prop=Step29721-testBlockUnblock                    
                    $errors = 1;                    
                }else { 
                    $issue->Commit();
                    $id = $issue->GetFieldValue("id")->GetValue;
                    $message = "Issue Created with ID: $id\n";
                    my $defectUrl = "#";
                    $createdDefectLinks_ref->{"$comment"} = "$message?url=$defectUrl"; #ie: ?url=http://www.google.com/ig
                }					
			};
			if ($@) {
				$message = "Error: failed trying to create issue, with error: $@ \n";
				print "$message";
				$errors = 1;				
			};			
		}else{#$mode eq "manual"
			$createdDefectLinks_ref->{"$comment"} = "Needs to File Defect?prop=$prop";#?prop=Step29721-testBlockUnblock
		}			
	}
	
	if (keys % {$createdDefectLinks_ref}) {
  		$propertyName_ref = "createdDefectLinks"; 
		$self->populatePropertySheetWithDefectLinks($createdDefectLinks_ref, $propertyName_ref);
		$self->createLinkToDefectReport("ClearQuest Report");
    }
    
  	if($errors && $errors ne ""){
    	print "Created Defects completed with some Errors\n"
    }
}

####################################################################
# fileDefect
#  
# Side Effects:
#   
# Arguments:
#   self -              the object reference
#   opts -              hash of options
#
# Returns:
#   Nothing
#
####################################################################
sub fileDefect {
    my ($self, $opts) = @_;
    
    my $prop = $opts->{prop};    
    if (!$prop || $prop eq "") {
		print "Error: prop does not exist or is empty\n";
		exit 1;
    }
    
    my $jobIdParam = $opts->{jobIdParam};    
    if (!$jobIdParam || $jobIdParam eq "") {
		print "Error: jobIdParam does not exist or is empty\n";
		exit 1;
    }
    
    my $cqSession = $self->getCQInstance();
    if (!$cqSession) {
        exit 1;
    }       
	
	print "Trying to get Property /$jobIdParam/ecTestFailures/$prop \n";	
	my ($jSuccess, $jXpath, $jMsg) = $self->InvokeCommander({SupressLog=>1,IgnoreError=>1}, "getProperties", {recurse => "0", jobId => "$jobIdParam", path => "/myJob/ecTestFailures/$prop"});
		
	##Properties##
	#stepID
	my $stepID = "N/A";		
	#testSuiteName
	my $testSuiteName = "N/A";
	#testCaseResult
	my $testCaseResult = "N/A";
	#testCaseName
	my $testCaseName = "N/A";
	#logs
	my $logs = "N/A";
	#stepName
	my $stepName = "N/A";
	
	my $jResults = $jXpath->find('//property');
	foreach my $jContext ($jResults->get_nodelist) {			
		my $subPropertyName = $jXpath->find('./propertyName', $jContext)->string_value;
		my $value = $jXpath->find('./value', $jContext)->string_value;
		
		if ($subPropertyName eq "stepId"){$stepID = $value;}			
		if ($subPropertyName eq "testSuiteName"){$testSuiteName = $value;}
		if ($subPropertyName eq "testCaseResult"){$testCaseResult = $value;}
		if ($subPropertyName eq "testCaseName"){$testCaseName = $value;}
		if ($subPropertyName eq "logs"){$logs = $value;}
		if ($subPropertyName eq "stepName"){$stepName = $value;}			
	}
	
	my $message = "";		
	my $comment = "Step ID: $stepID "
				. "Step Name: $stepName "
				. "Test Case Name: $testCaseName ";
					
	eval{	    
        $issue = $cqSession->BuildEntity("defect");
        #$cqSession->EditEntity($issue, "modify");
		
        #Shoud set headline, severity = 3 (Average), description
        $issue->SetFieldValue("Headline", "Defect: $prop");
        $issue->SetFieldValue("Severity", "3-Average");
        $issue->SetFieldValue("Description", "$comment");
        
        $status = $issue->Validate();
        if ($status) {                  
            $issue->Revert();
            $message = "Error: failed trying to create defect, with error: $status \n";
            print "$message \n";
            print "setProperty name: /$jobIdParam/createdDefectLinks/$comment value:$message?prop=$prop \n";
            my ($success, $xpath, $msg) = $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1},
             "setProperty", "/myJob/createdDefectLinks/$comment", "$message?prop=$prop", {jobId => "$jobIdParam"});                    
            $errors = 1;                    
        }else { 
            $issue->Commit();
            $id = $issue->GetFieldValue("id")->GetValue;
            $message = "Issue Created with ID: $id\n";
            my $defectUrl = "#";
            my ($success, $xpath, $msg) = $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1},
             "setProperty", "/myJob/ecTestFailures/$prop/defectId", "$id", {jobId => "$jobIdParam"});
            my ($success, $xpath, $msg) = $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1},
             "setProperty", "/myJob/createdDefectLinks/$comment", "$message?url=$defectUrl", {jobId => "$jobIdParam"});                       
        }			 
		
	};
	if ($@) {
		$message = "Error: failed trying to create issue, with error: $@ \n";
		print "$message \n";
		print "setProperty name: /$jobIdParam/createdDefectLinks/$comment value:$message?prop=$prop \n";
		my ($success, $xpath, $msg) = $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1},
			 "setProperty", "/myJob/createdDefectLinks/$comment", "$message?prop=$prop", {jobId => "$jobIdParam"});
		#exit 1;
	};
}

####################################################################
# getCQInstance
#
# Side Effects:
#   
# Arguments:
#   self -              the object reference
#
# Returns:
#   A clearquest session used to do operations on a CQ server.
####################################################################
sub getCQInstance
{
    my ($self) = @_;
    
    my $cfg = $self->getCfg();

    my $database = $cfg->get('database');
    my $schema = $cfg->get('schema');

    my $credentialName = $cfg->getCredential();
    my $credentialLocation = q{/projects/$[/plugins/EC-DefectTracking/project]/credentials/}.$credentialName;

    my ($success, $xPath, $msg) = $self->InvokeCommander({SupressLog=>1,IgnoreError=>1}, "getFullCredential", $credentialLocation);
    if (!$success) {
		print "\nError getting credential\n";	
		return;
    }

    $user = $xPath->findvalue('//userName')->value();
    $passwd = $xPath->findvalue('//password')->value();
	
	eval 'use Win32::OLE qw(in)';
    die "Unable to load Win32::OLE module: $@\n" if $@;
	
	print "Creating ClearQuest Session\n";
	my ($sessionObj) = Win32::OLE->new('Clearquest.Session');
		
    #$sessionObj = CQSession::Build();

    eval {
		print "Logging onto ClearQuest Session\n";
		#$sessionObj->UserLogon("admin", "", "SAMPL", "2", "clearquest");
		$sessionObj->UserLogon("$user", "$passwd", "$database", $AD_PRIVATE_SESSION, "$schema");
		#$sessionObj->UserLogon("$user","$passwd","$database","$schema");
		#$sessionObj->UserLogon("admin","","SAMPL","");
    };    
    if ($@) {
       my $actualErrorMsg = $@;       
       print "Error trying to get ClearQuest connection for Database=$database, Schema=$schema with user=$user\n";
		if ($msg ne "") {
			print "$msg\n";
		} else {
			print "$actualErrorMsg\n";
		}
       return;
    }
	
	print "ClearQuest Session Created and logged in $sessionObj\n";
	
	if($sessionObj){
		return $sessionObj;
	}else{
		print "Error trying to get ClearQuest connection for Database=$database, Schema=$schema with user=$user\n";
		return;
	}
}

####################################################################
# getConfigUser
#
# Side Effects:
#   
# Arguments:
#   self -              the object reference
#
# Returns:
#   Gets the user on the CQ config
####################################################################
sub getConfigUser
{
    my ($self) = @_;
    
    my $cfg = $self->getCfg();
    
    my $credentialName = $cfg->getCredential();
    my $credentialLocation = q{/projects/$[/plugins/EC-DefectTracking/project]/credentials/}.$credentialName;

    my ($success, $xPath, $msg) = $self->InvokeCommander({SupressLog=>1,IgnoreError=>1}, "getFullCredential", $credentialLocation);
    if (!$success) {
		print "\nError getting credential\n";	
		return;
    }

    $user = $xPath->findvalue('//userName')->value();
    return $user;
}

####################################################################
# queryDefectSystemWithDefectID
#
# Side Effects:
#   
# Arguments:
#   self -              the object reference
#   defectID -          the defect id to use in the query
#   cqSession -         the clearquest session used to connect to the 
#                       CLEARQUEST server
# Returns:
#   A tuple: (<name of url> , <url pointing to a defect id>)
####################################################################
sub queryDefectSystemWithDefectID {

    my ($self, $defectID, $cqSession) = @_;

    print "Query with Session:$cqSession\n";
	
	my $issue;
    eval {
        $issue = $cqSession->GetEntity("defect", $defectID);
    };
    if ($@) {
       my $actualErrorMsg = $@;       
       print "Error trying to get CQ defect=$defectID: ";       
       print "$actualErrorMsg\n";       
       return;
    }
	
	print "Issue: $issue\n";

    my $summary = $issue->GetFieldValue("headline")->GetValue;
    my $status = $issue->GetFieldValue("state")->GetValue;
    my $project = $issue->GetFieldValue("project")->GetValue;    
    my $name = "$defectID: $summary, PROJECT:$project STATUS=$status";

    #my $url = $self->getCfg()->get('url') . "/browse/$defectID";
    my $url = "#";

    return ($name, $url);
}

####################################################################
# queryDefectSystemWithDefectIDUpdated
#
# Side Effects:
#   
# Arguments:
#   self -              the object reference
#   defectID -          the defect id to use in the query
#   cqSession -         the CQ instance used to connect to the 
#                       CQ server
#	message -			Result Message
# Returns:
#   A tuple: (<name of url> , <url pointing to a defect id>)
####################################################################
sub queryDefectSystemWithDefectIDUpdated {
    
    my ($self, $defectID, $cqSession, $message) = @_;

    my $issue;
    eval {
        $issue = $cqSession->GetEntity("defect", $defectID);
    };
    if ($@) {
       my $actualErrorMsg = $@;       
       print "Error trying to get CQ defect=$defectID: ";       
       print "$actualErrorMsg\n";       
       return;
    }

    my $summary = $issue->GetFieldValue("headline")->GetValue;
    my $status = $issue->GetFieldValue("state")->GetValue;
    my $project = $issue->GetFieldValue("project")->GetValue;
    
    my $name = "$defectID: $summary, PROJECT:$project STATUS=$status, RESULT=$message";   

    #my $url = $self->getCfg()->get('url') . "/browse/$defectID";
    my $url = "#";

    return ($name, $url);
}

####################################################################
# addConfigItems
# 
# Side Effects:
#   
# Arguments:
#   self -              the object reference
#   opts -              hash of options   
#
# Returns:
#   nothing
####################################################################
sub addConfigItems{
    my ($self, $opts) = @_;
    $opts->{'linkDefects_label'} = "ClearQuest Report";
    $opts->{'linkDefects_description'} = "Generates a report of ClearQuest IDs found in the build.";
}

1;
