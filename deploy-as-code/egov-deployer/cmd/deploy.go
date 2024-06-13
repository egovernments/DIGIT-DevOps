/*
Copyright © 2019 NAME HERE <EMAIL ADDRESS>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/
package cmd

import (
	"errors"

	"egov-deployer/pkg/cmd/deployer"

	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

var options deployer.Options

// deployCmd represents the deploy command
var deployCmd = &cobra.Command{
	Use:   "deploy [IMAGES]",
	Short: "Deploy a comma separated list of images",
	Long: `A longer description that spans multiple lines and likely contains examples
and usage of using your command. For example:

Cobra is a CLI library for Go that empowers applications.
This application is a tool to generate the needed files
to quickly create a Cobra application.`,

	PreRunE: func(cmd *cobra.Command, args []string) error {
		if options.DesiredProduct == "" && len(args) < 1 {
			return errors.New("Image Deploy: At least require one image to deploy")
		}

		if options.DesiredProduct == "" && len(args) >= 1 {
			options.Images = args[0]
		}

		return nil
	},
	Run: func(cmd *cobra.Command, args []string) {
		// fmt.Println("deploy called with images: " + args[0])

		options.HelmDir = viper.GetString("helm-dir")
		deployer.DeployCharts(options)
	},
}

func init() {
	// deployCmd.Flags().StringVarP(&images, "images", "i", "", "Images to be deployed")

	deployCmd.Flags().String("helm-dir", "../helm", "Helm Charts / Configs directory")
	viper.BindPFlag("helm-dir", deployCmd.Flags().Lookup("helm-dir"))

	deployCmd.Flags().StringVarP(&options.DesiredProduct, "product", "s", "", "Desired Product stack")
	deployCmd.Flags().StringVarP(&options.ProductVersion, "version", "v", "", "Intented product version to be applied")
	deployCmd.Flags().StringVarP(&options.Environment, "environment", "e", "", "Environment override to be applied")
	deployCmd.Flags().BoolVarP(&options.ClusterConfigs, "cluster-configs", "c", false, "Deploy cluster configs")
	deployCmd.Flags().BoolVarP(&options.Print, "print", "p", false, "Print templates to stdout")
	// deployCmd.MarkFlagRequired("images")
	deployCmd.MarkFlagRequired("environment")
	rootCmd.AddCommand(deployCmd)

}
