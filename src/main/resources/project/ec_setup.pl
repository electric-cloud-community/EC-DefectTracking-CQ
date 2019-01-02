my $projPrincipal = "project: $pluginName";
my $baseProj = '$[/plugins/EC-DefectTracking/project]';

if ($promoteAction eq 'promote') {
    # Register our type with the base DefectTracking plugin
    $batch->setProperty("/plugins/EC-DefectTracking/project/defectTracking_types/@PLUGIN_KEY@", "CLEARQUEST");
    
    # Give our project principal execute access to the base project
    my $xpath = $commander->getAclEntry("user", $projPrincipal,
                                        {projectName => $baseProj});
    if ($xpath->findvalue('//code') eq 'NoSuchAclEntry') {
        $batch->createAclEntry("user", $projPrincipal,
                               {projectName => $baseProj,
                                executePrivilege => "allow"});
		
    }
} elsif ($promoteAction eq 'demote') {
    # unregister with the base
    $batch->deleteProperty("/plugins/EC-DefectTracking/project/defectTracking_types/@PLUGIN_KEY@");
    
    # remove permissions
    my $xpath = $commander->getAclEntry("user", $projPrincipal,
                                        {projectName => $baseProj});
    if ($xpath->findvalue('//principalName') eq $projPrincipal) {
        $batch->deleteAclEntry("user", $projPrincipal,
                               {projectName => $baseProj});
    }
	
}

# Data that drives the create step picker registration for this plugin.
my $defectSystem = "ClearQuest";
my %createStep = (
    label       => "$defectSystem - Create Defects",
    procedure   => "CreateDefects",
    description => "Create $defectSystem defects based on test failures in a job.",
    category    => "Defect Tracking"
);
my %linkStep = (
    label       => "$defectSystem - Link Defects",
    procedure   => "LinkDefects",
    description => "Link existing $defectSystem defects to a job.",
    category    => "Defect Tracking"
);
my %updateStep = (
    label       => "$defectSystem - Update Defects",
    procedure   => "UpdateDefects",
    description => "Automatically update defects in $defectSystem.",
    category    => "Defect Tracking"
);

$batch->deleteProperty("/server/ec_customEditors/pickerStep/ClearQuest - Create Defects");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/ClearQuest - Link Defects");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/ClearQuest - Update Defects");

@::createStepPickerSteps = (\%createStep, \%linkStep, \%updateStep);
