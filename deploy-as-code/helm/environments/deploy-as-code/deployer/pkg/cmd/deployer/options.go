package deployer

type Options struct {
	ConfigDir      string
	Images         string
	Environment    string
	ClusterConfigs bool
	Print          bool
}

// func (o *Options) SetImages(images string) {
// 	o.images = images
// }

// func (o Options) Images() string {
// 	return o.images

// }

// func (o Options) Environment() string {
// 	return o.environment

// }

// func (o Options) ClusterConfigs() bool {
// 	return o.clusterConfigs

// }

// func (o Options) DryRun() bool {
// 	return o.dryRun

// }

// func (o Options) Print() bool {
// 	return o.print

// }
