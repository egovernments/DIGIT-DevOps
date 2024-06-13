package deployer

type Options struct {
	DesiredProduct string
	ProductVersion string
	HelmDir        string
	Images         string
	Environment    string
	ClusterConfigs bool
	Print          bool
}
