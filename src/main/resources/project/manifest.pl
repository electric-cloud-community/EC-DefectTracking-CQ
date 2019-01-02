@files = (
    ['//property[propertyName="ECDefectTracking::CQ::Cfg"]/value', 'CQCfg.pm'],
    ['//property[propertyName="ECDefectTracking::CQ::Driver"]/value', 'CQDriver.pm'],
    ['//property[propertyName="createConfig"]/value', 'cqCreateConfigForm.xml'],
    ['//property[propertyName="editConfig"]/value', 'cqEditConfigForm.xml'],
    ['//property[propertyName="ec_setup"]/value', 'ec_setup.pl'],
	['//procedure[procedureName="LinkDefects"]/propertySheet/property[propertyName="ec_parameterForm"]/value', 'ec_parameterForm-LinkDefects.xml'],	
	['//procedure[procedureName="UpdateDefects"]/propertySheet/property[propertyName="ec_parameterForm"]/value', 'ec_parameterForm-UpdateDefects.xml'],	
	['//procedure[procedureName="CreateDefects"]/propertySheet/property[propertyName="ec_parameterForm"]/value', 'ec_parameterForm-CreateDefects.xml'],	
);
