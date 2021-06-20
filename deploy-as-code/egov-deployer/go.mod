module github.com/egovernments/DIGIT-DevOps/deploy-as-code/egov-deployer

go 1.13

require (
	github.com/manifoldco/promptui v0.8.0
	github.com/mitchellh/go-homedir v1.1.0
	github.com/spf13/cobra v0.0.5
	github.com/spf13/viper v1.6.1
	gopkg.in/yaml.v2 v2.2.4
)

replace github.com/egovernments/DIGIT-DevOps/deploy-as-code/egov-deployer => ../egov-deployer
