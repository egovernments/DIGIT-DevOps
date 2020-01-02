package deployer

import (
	"bytes"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

func DeployCharts(options Options) {

	helmDir, _ := filepath.Abs(options.HelmDir)
	fmt.Println("Helm Directory - " + helmDir)

	envOverrideFile := filepath.FromSlash(fmt.Sprintf(helmDir+"/environments/%s.yaml", options.Environment))

	if options.ClusterConfigs {
		envSecretFile := filepath.FromSlash(fmt.Sprintf(helmDir+"/environments/%s-secrets.yaml", options.Environment))
		deployClusterConfigs(helmDir, envOverrideFile, envSecretFile)
	}

	services := strings.Split(options.Images, ",")
	for _, service := range services {

		log.Printf("------------------------------------ DEPLOYING %s ------------------------------------", service)
		repository, tag := getDockerComponents(service)
		serviceChartDirectory, err := getServiceChartDirectory(helmDir, repository)

		if err == nil && serviceChartDirectory != "" {
			log.Println(serviceChartDirectory)
		} else {
			log.Panicln("Service chart not found: " + repository)
		}

		if tag == "" {
			clusterImage := getImageTagFromCluster(repository)
			if clusterImage == "" {
				log.Panicln("Image tag not found")
			}
			_, tag = getDockerComponents(clusterImage)
			log.Printf("Fetched image from cluster, %s:%s", repository, tag)
		}

		helmDepUpdate := "helm dep update"

		execCommand(helmDepUpdate, serviceChartDirectory)

		if !options.Print {
			tmpDir, err := ioutil.TempDir(os.TempDir(), "helm-")
			if err != nil {
				log.Panicln("Cannot create temporary directory", err)
			}

			// Clean up folder after function exists
			defer os.RemoveAll(tmpDir)

			log.Printf("Generating final manifests to directory : %s ", tmpDir)
			helmTemplate := fmt.Sprintf("helm template --output-dir %s -f %s --set image.tag=%s --set initContainers.dbMigration.image.tag=%s .", tmpDir, envOverrideFile, tag, tag)
			execCommand(helmTemplate, serviceChartDirectory)

			log.Println("Applying manifests to the cluster ")
			kubeApplyCmd := "kubectl apply -f ."
			out := execCommand(kubeApplyCmd, tmpDir+string(os.PathSeparator)+repository+string(os.PathSeparator)+"templates")
			log.Println(out.String())

		} else {
			helmTemplate := fmt.Sprintf("helm template -f %s --set image.tag=%s --set initContainers.dbMigration.image.tag=%s .", envOverrideFile, tag, tag)
			out := execCommand(helmTemplate, serviceChartDirectory)
			fmt.Println(out.String())
		}

	}

}

func getImageTagFromCluster(service string) (tag string) {
	kubectlGetImageCmd := fmt.Sprintf("kubectl get deployment %s -o=jsonpath='{$.spec.template.spec.containers[:1].image}'", service)

	output := execCommandRaw(kubectlGetImageCmd, "", true)
	return strings.ReplaceAll(output.String(), "'", "")

}

func deployClusterConfigs(helmDir string, envOverrideFile string, envSecretFile string) {

	log.Println("------------------------------------ DEPLOYING CLUSTER CONFIGS ------------------------------------")
	clusterConfigDir, err := getServiceChartDirectory(helmDir, "cluster-configs")

	if err == nil && clusterConfigDir != "" {
		fmt.Println(clusterConfigDir)
	} else {
		log.Panicln("Cluster configs not found", err)
	}

	tmpDir, err := ioutil.TempDir(os.TempDir(), "helm-")
	if err != nil {
		log.Panicln("Failed to create temporary directory", err)
	}

	tmpDecFile, err := ioutil.TempFile(tmpDir, "helm-dec-")
	if err != nil {
		log.Panicln("Failed to create temporary file", err)
	}
	// Clean up folder after function exists
	defer os.RemoveAll(tmpDir)

	sopsDecryptCmd := fmt.Sprintf("sops -d --output %s %s", tmpDecFile.Name(), envSecretFile)
	execCommand(sopsDecryptCmd, helmDir)

	helmTemplate := fmt.Sprintf("helm template --output-dir %s -f %s -f %s .", tmpDir, envOverrideFile, tmpDecFile.Name())
	execCommand(helmTemplate, clusterConfigDir)

	kubeApplyCmd := "kubectl apply -f ."
	out := execCommand(kubeApplyCmd, tmpDir+string(os.PathSeparator)+"cluster-configs"+string(os.PathSeparator)+"templates")
	log.Println(out.String())
}

func getDockerComponents(image string) (repository string, tag string) {
	image = strings.Trim(strings.Replace(image, "-db:", ":", 1), " ")
	components := strings.Split(image, ":")

	if len(components) == 2 {
		tag = components[1]
	}

	domainComponents := strings.Split(components[0], "/")
	repository = domainComponents[len(domainComponents)-1]

	return
}

func getServiceChartDirectory(baseDirectory string, service string) (serviceChartDirectory string, err error) {

	err = filepath.Walk(baseDirectory,
		func(path string, info os.FileInfo, err error) error {
			if err != nil {
				return err
			}
			if info.IsDir() && strings.EqualFold(info.Name(), service) {
				serviceChartDirectory = path
			}
			return nil
		})

	return serviceChartDirectory, err
}

func execCommand(command string, commandDirectory string) (out bytes.Buffer) {
	return execCommandRaw(command, commandDirectory, false)
}

func execCommandRaw(command string, commandDirectory string, suppressErrors bool) (out bytes.Buffer) {
	var err error
	parts := strings.Fields(command)
	head := parts[0]
	parts = parts[1:len(parts)]

	// fmt.Println(command)
	cmd := exec.Command(head, parts...)
	var output bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &output
	cmd.Stderr = &stderr
	if commandDirectory != "" {
		if _, err := os.Stat(commandDirectory); err == nil {
			cmd.Dir = commandDirectory
		} else {
			log.Panicln("Error applying manifests ", err)
		}
	}
	err = cmd.Run()
	if err != nil && !suppressErrors {
		log.Panicln(fmt.Sprint(err) + ": " + stderr.String())
	}
	return output
}
