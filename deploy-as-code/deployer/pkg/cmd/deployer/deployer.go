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

// DeployCharts deploys render all charts using helm template and deploy them using kubectl apply --recursive
func DeployCharts(options Options) {

	configDir, _ := filepath.Abs(options.ConfigDir)
	var helmDir = configDir + "helm"
	log.Println(configDir)
	log.Println("Helm Directory - " + helmDir)

	index := buildIndex(helmDir)
	envOverrideFile := filepath.FromSlash(fmt.Sprintf(configDir+"/environments/%s.yaml", options.Environment))

	if options.ClusterConfigs && !options.Print {
		envSecretFile := filepath.FromSlash(fmt.Sprintf(configDir+"/environments/%s-secrets.yaml", options.Environment))
		deployClusterConfigs(index, helmDir, envOverrideFile, envSecretFile)
	}

	services := strings.Split(options.Images, ",")
	for _, service := range services {

		var name, helmTemplate, args = "", "", make([]string, 0, 10)

		log.Printf("------------------------------------ DEPLOYING %s ------------------------------------", service)
		repository, tag := getDockerComponents(service)
		serviceChartDirectory, ok := index[repository]

		name = repository
		args = append(args, fmt.Sprintf("-f %s", envOverrideFile))
		args = append(args, fmt.Sprintf("--set name=%s", name))

		if ok && serviceChartDirectory != "" {
			log.Println(serviceChartDirectory)
		} else {
			log.Panicln("Service chart not found: " + repository)
		}

		if tag == "" {
			clusterImage := getImageTagFromCluster(name)
			if clusterImage != "" {
				_, tag = getDockerComponents(clusterImage)
				args = append(args, fmt.Sprintf("--set image.tag=%s", tag))
				args = append(args, fmt.Sprintf("--set initContainers.dbMigration.image.tag=%s", tag))
				log.Printf("Fetched image from cluster, %s:%s", repository, tag)
			}
		} else {
			args = append(args, fmt.Sprintf("--set image.tag=%s", tag))
			args = append(args, fmt.Sprintf("--set initContainers.dbMigration.image.tag=%s", tag))
		}

		altServiceOverrideFile := filepath.FromSlash(fmt.Sprintf(serviceChartDirectory+"/%s-values.yaml", name))
		if _, err := os.Stat(altServiceOverrideFile); err == nil {
			args = append(args, fmt.Sprintf("-f %s", altServiceOverrideFile))
			log.Printf("Applying values from %s-values.yaml", name)
		}

		helmDepUpdate := "helm dep update"
		execCommand(helmDepUpdate, serviceChartDirectory)

		if !options.Print {
			tmpDir, err := ioutil.TempDir(os.TempDir(), "helm-")
			if err != nil {
				log.Panicln("Cannot create temporary directory", err)
			}

			deployCrds(serviceChartDirectory)
			// Clean up folder after function exists
			defer os.RemoveAll(tmpDir)
			args = append(args, fmt.Sprintf("--output-dir %s", tmpDir))

			log.Printf("Generating final manifests to directory : %s ", tmpDir)
			helmTemplate = fmt.Sprintf("helm template %s .", strings.Join(args[:], " "))
			execCommand(helmTemplate, serviceChartDirectory)

			log.Println("Applying manifests to the cluster ")
			kubeApplyCmd := "kubectl apply --recursive  -f ."
			out := execCommand(kubeApplyCmd, tmpDir)
			log.Println(out.String())

		} else {
			helmTemplate = fmt.Sprintf("helm template %s .", strings.Join(args[:], " "))
			log.Printf("Executing %s", helmTemplate)
			out := execCommand(helmTemplate, serviceChartDirectory)
			fmt.Println(out.String())
		}

	}

}

func deployCrds(serviceChartDirectory string) {
	crdsDirectory := serviceChartDirectory + string(os.PathSeparator) + "crds"
	if _, err := os.Stat(crdsDirectory); err == nil {
		log.Println("CRDS Directory found, applying CRDS!")
		applyCrds := fmt.Sprintf("kubectl apply --recursive  -f  %s", serviceChartDirectory+string(os.PathSeparator)+"crds")

		out := execCommandRaw(applyCrds, serviceChartDirectory, false)
		log.Println(out.String())
	}

}

func getImageTagFromCluster(service string) (tag string) {
	kubectlGetImageCmd := fmt.Sprintf("kubectl get deployments -l app=%s --all-namespaces -o=jsonpath={.items[*].spec.template.spec.containers[:1].image}", service)

	output := execCommandRaw(kubectlGetImageCmd, "", true)
	return output.String()

}

func deployClusterConfigs(index map[string]string, configDir string, envOverrideFile string, envSecretFile string) {

	log.Println("------------------------------------ DEPLOYING CLUSTER CONFIGS ------------------------------------")
	clusterConfigDir, ok := index["cluster-configs"]

	if ok && clusterConfigDir != "" {
		fmt.Println(clusterConfigDir)
	} else {
		log.Panicln("Cluster configs not found")
	}

	var args = make([]string, 0, 10)

	args = append(args, fmt.Sprintf("-f %s", envOverrideFile))

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
	args = append(args, fmt.Sprintf("--output-dir %s", tmpDir))
	fmt.Println("Before Trimming" + configDir)

	sopsDir := strings.Trim(configDir, "helm")
	fmt.Println("path too sops" + sopsDir)
	if _, err := os.Stat(sopsDir + "/.sops.yaml"); os.IsNotExist(err) {
		fmt.Println("Error Condition: ")
		fmt.Println(err)
		args = append(args, fmt.Sprintf("-f %s", envSecretFile))
	} else {
		sopsDecryptCmd := fmt.Sprintf("sops -d --output %s %s", tmpDecFile.Name(), envSecretFile)
		execCommand(sopsDecryptCmd, configDir)
		args = append(args, fmt.Sprintf("-f %s", tmpDecFile.Name()))
	}

	helmTemplate := fmt.Sprintf("helm template %s .", strings.Join(args[:], " "))
	log.Println(helmTemplate)
	execCommand(helmTemplate, clusterConfigDir)

	kubeApplyCmd := "kubectl apply --recursive -f ."
	out := execCommandRaw(kubeApplyCmd, tmpDir+string(os.PathSeparator)+"cluster-configs"+string(os.PathSeparator)+"templates", false)
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

func buildIndex(chartsDirectory string) (m map[string]string) {
	m = make(map[string]string)
	filepath.Walk(chartsDirectory,
		func(path string, info os.FileInfo, err error) error {
			if err != nil {
				return err
			}

			if strings.Contains(info.Name(), "values.yaml") {
				if strings.EqualFold(info.Name(), "values.yaml") {
					addToMap(m, filepath.Base(filepath.Dir(path)), filepath.Dir(path))
				} else {
					svc := strings.Replace(info.Name(), "-values.yaml", "", 1)
					addToMap(m, svc, filepath.Dir(path))
				}
			}

			return nil
		})

	return m

}

func addToMap(m map[string]string, k string, v string) {
	if _, ok := m[k]; ok {
		log.Printf("Duplicate service found %s! This will lead to undesired results, fix it! \n", k)
	}

	m[k] = v
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
