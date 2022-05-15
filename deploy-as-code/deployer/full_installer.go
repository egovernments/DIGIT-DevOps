package main

import (
	"bytes"
	"container/list"
	"errors"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"math/rand"
	"os"
	"os/exec"
	"strconv"
	"strings"
	s "strings"

	"github.com/manifoldco/promptui"
	"gopkg.in/yaml.v2"
	//"bufio"
)

var Reset = "\033[0m"
var Red = "\033[31m"
var Green = "\033[32m"
var Yellow = "\033[33m"
var Blue = "\033[34m"
var Purple = "\033[35m"
var Cyan = "\033[36m"
var Gray = "\033[37m"
var White = "\033[97m"

//Defining a struct to parse the yaml file
type Digit struct {
	Version string `yaml:"version"`
	Modules []struct {
		Name         string   `yaml:"name"`
		Services     []string `yaml:"services"`
		Dependencies []string `yaml:"dependencies,omitempty"`
	} `yaml:"modules"`
}

type Set struct {
	set map[string]bool
}

func NewSet() *Set {
	return &Set{make(map[string]bool)}
}
func (set *Set) Add(i string) bool {
	_, found := set.set[i]
	set.set[i] = true
	return !found //False if it existed already
}
func (set *Set) Get(i string) bool {
	_, found := set.set[i]
	return found
}

func main() {

	var optedInfraType string          // Infra types supported to deploy DIGIT
	var servicesToDeploy string        // Modules to be deployed
	var number_of_worker_nodes int = 1 // No of VMs for the k8s worker nodes
	var optedCloud string              // Desired InfraType to deploy
	var cloudTemplate string           // Which terraform template to choose
	var cloudLoginCredentials bool     // Is there a valid cloud account and credentials

	infraType := []string{
		"0. You have an existing kubernetes Cluster ready, you would like to leverage it to setup DIGIT on that",
		"1. Pilot/POC (Just for a POC to Quickstart and explore",
		"2. DevTest Setup (You to setup and build/customize and test",
		"3. Bare Minimal (95% reliability), 10 concurrent gov services per sec",
		"4. Medium (99.99% reliability), 100 concurrent gov services per sec",
		"5. High (99.99% reliability), 1000 concurrent gov services per sec",
		"6. For custom options, use this calcualtor to determine the required nodes (https://docs.digit.org/Infra-calculator)"}

	cloudPlatforms := []string{
		"0. Local machine/Your Existing VM",
		"1. AWS-EC2 - Quickstart with a Single EC2 Instace on AWS",
		"2. AWS-EKS - Production grade Elastic Kubernetes Service (EKS)",
		"3. AZURE-AKS - Production grade Azure Kubernetes Service (AKS)",
		"4. GOOGLE CLOUD - Production grade Google Kubernetes Engine (GKE)",
		"5. On-prem/Private Cloud - Quickstart with Single VM",
		"6. On-prem/Privare Cloud - Production grade Kubernetes Cluster Setup"}

	fmt.Println(string(Green), "\n*******  Welcome to DIGIT Server setup & Deployment !!! ******** \n\n Please read the detailed Pre-requsites from the below link before you proceed *********\n https://docs.digit.org/Infra-calculator\n")
	const sPreReq = "Pre-requsites (Please Read Carefully):\nvDIGIT Stack is a combination of many microservices that are packaged as docker containers that can be run on any container supported platforms like dockercompose, kubernetes, etc. Here we'll have a setup baselined for kubernetes.\nHence the following are mandatory to have it before you proceed.\n\t1. Kubernetes(K8s) Cluster.\n\t\t[a] Local: If you do not have k8s, using this link you can create k8s cluster on your local or on a VM.\n\t\t[b] Cloud: If you have your cloud account like AWS, Azure, GCP, SDC or NIC you can follow this link to create k8s.\n\t2. Post the k8s cluster creation you should get the Kubeconfig file, which you have saved in your local machine.\n\t\n\n Well! Let's get started with the DIGIT Setup process, if you want to abort any time press (Ctl+c), you can always come back and rerun the script."
	fmt.Println(string(Cyan), sPreReq)

	preReqConfirm := []string{"Yes", "No"}
	var proceed string = ""
	proceed, _ = sel(preReqConfirm, "Are you good to proceed?")
	if proceed == "Yes" {
		optedInfraType, _ = sel(infraType, "Select the below suitable infra option for your usecase")
		switch optedInfraType {
		case infraType[0]:
			number_of_worker_nodes = 0
		case infraType[1]:
			number_of_worker_nodes = 1
		case infraType[2]:
			number_of_worker_nodes = 2
		case infraType[3]:
			number_of_worker_nodes = 3 //TBD
		case infraType[4]:
			number_of_worker_nodes = 4 //TBD
		case infraType[5]:
			number_of_worker_nodes = 5 //TBD
		case infraType[6]:
			number_of_worker_nodes, _ = strconv.Atoi(enterValue(nil, "How many VM/nodes are required based on the calculation"))
		default:
			number_of_worker_nodes = 0
		}

		servicesToDeploy = selectGovServicesToInstall()

		optedCloud, _ = sel(cloudPlatforms, "Choose the cloud type to provision the required servers for the selectdd gov stack services?")

		switch optedCloud {
		case cloudPlatforms[1]:
			var optedAccessType string
			var aws_access_key string
			var aws_secret_key string
			var aws_session_key string

			cloudTemplate = "quickstart-aws-ec2"

			accessTypes := []string{"Root Admin", "Temprory Admin"}
			optedAccessType, _ = sel(accessTypes, "Choose your AWS access type? eg: If your access is session based unlike root admin")

			fmt.Println("\n Great, you need to input your " + optedCloud + "credentials to provision the cloud resources ..\n")
			fmt.Println("Input the AWS access key id")
			fmt.Scanln(&aws_access_key)

			fmt.Println("\nInput the AWS secret key")
			fmt.Scanln(&aws_secret_key)

			fmt.Println("\nInput the AWS Session Token")
			fmt.Scanln(&aws_session_key)

			if optedAccessType == "Temprory Admin" {
				cloudLoginCredentials = awsloginWithSession(aws_access_key, aws_secret_key, aws_session_key)
			} else {
				cloudLoginCredentials = awslogin(aws_access_key, aws_secret_key)
			}

		case cloudPlatforms[2]:
			var optedAccessType string
			var aws_access_key string
			var aws_secret_key string
			var aws_session_key string

			cloudTemplate = "sample-aws"

			accessTypes := []string{"Root Admin", "Temprory Admin"}
			optedAccessType, _ = sel(accessTypes, "Choose your AWS access type? eg: If your access is session based unlike root admin")

			fmt.Println("\n Great, you need to input your " + optedCloud + "credentials to provision the cloud resources ..\n")
			fmt.Println("Input the AWS access key id")
			fmt.Scanln(&aws_access_key)

			fmt.Println("\nInput the AWS secret key")
			fmt.Scanln(&aws_secret_key)

			fmt.Println("\nInput the AWS Session Token")
			fmt.Scanln(&aws_session_key)

			if optedAccessType == "Temprory Admin" {
				cloudLoginCredentials = awsloginWithSession(aws_access_key, aws_secret_key, aws_session_key)
			} else {
				cloudLoginCredentials = awslogin(aws_access_key, aws_secret_key)
			}

		case cloudPlatforms[3]:
			cloudTemplate = "sample-azure"
			fmt.Println("\n Great, you need to input your " + optedCloud + "credentials to provision the cloud resources ..\n")
			azure_username := enterValue(nil, "Please enter your AZURE UserName")
			azure_password := enterValue(nil, "Enter your AZURE Password")
			cloudLoginCredentials = azurelogin(azure_username, azure_password)

		case cloudPlatforms[4]:
			cloudTemplate = "sample-gcp"
			fmt.Println("\n Great, you need to input your " + optedCloud + "credentials to provision the cloud resources ..\n")
			fmt.Println("Support for the " + optedCloud + "is still underway ... you need to wait")

		case cloudPlatforms[5]:
			cloudTemplate = "sample-private-cloud"
			fmt.Println("\n Great, you need to input your " + optedCloud + "credentials to provision the cloud resources ..\n")
			fmt.Println("Support for the " + optedCloud + "is still underway ... you need to wait")

		default:
			//fmt.Println("\n Great, you need to input your " + optedCloud + "credentials to provision the cloud resources ..\n")
			//fmt.Println("Support for the " + optedCloud + "is still underway ... you need to wait")
		}
	}

	if cloudLoginCredentials {
		fmt.Println(string(Green), "\n*******  Let's proceed with cluster creation, please input the requested details below *********\n")
		cluster_name := enterValue(nil, "How do you want to name the Cluster? \n eg: your-name_dev or your-name_poc \n Make sure that this name is unique if you are trying for the consecutive times, possibly a duplicate DNS entry under digit.org domain could be mapped already")
		s3_bucket_tfstore := cluster_name + "-tf-store-" + strconv.Itoa(rand.Int())
		dir := "DIGIT-DevOps"
		gitCmd := ""
		_, err := os.Stat(dir)
		if os.IsNotExist(err) {
			gitCmd = fmt.Sprintf("git clone -b release https://github.com/egovernments/DIGIT-DevOps.git %s", dir)
		} else {
			gitCmd = fmt.Sprintf("git -C %s pull", dir)
		}
		execCommand(gitCmd)

		db_pswd := enterValue(nil, "What should be the database password to be created, it should be 8 char min")

		execSingleCommand(fmt.Sprintf("terraform init %s/infra-as-code/terraform/%s", dir, cloudTemplate))

		execSingleCommand(fmt.Sprintf("terraform plan -var=\"bucket_name=%s\" -var=\"cluster_name=%s\" -var=\"db_password=%s\" -var=\"number_of_worker_nodes=%d\" %s/infra-as-code/terraform/%s", s3_bucket_tfstore, cluster_name, db_pswd, number_of_worker_nodes, dir, cloudTemplate))

		execSingleCommand(fmt.Sprintf("terraform apply -var=\"bucket_name=%s\" -var=\"cluster_name=%s\" -var=\"db_password=%s\" -var=\"number_of_worker_nodes=%d\" %s/infra-as-code/terraform/%s", s3_bucket_tfstore, cluster_name, db_pswd, number_of_worker_nodes, dir, cloudTemplate))

	}

	contextset := setClusterContext()
	if contextset {
		deployCharts(servicesToDeploy, prepareDeploymentConfig(optedInfraType))
	}

	//terraform output to a file
	//replace the env values with the tf output
	//save the kubetconfig and set the currentcontext
	//set dns in godaddy using the api's

	fmt.Println("")
	endScript()
}

func getService(fullChart Digit, service string, set Set, svclist *list.List) {
	for _, s := range fullChart.Modules {
		if s.Name == service {
			if set.Add(service) {
				svclist.PushFront(service) //Add services into the list
				if s.Dependencies != nil {
					for _, deps := range s.Dependencies {
						getService(fullChart, deps, set, svclist)
					}
				}
			}
		}
	}
}

func execCommand(command string) error {
	var err error
	parts := strings.Fields(command)
	//	The first part is the command, the rest are the args:
	head := parts[0]
	args := parts[1:len(parts)]
	//	Format the command

	log.Println(string(Blue), " ==> "+command)
	cmd := exec.Command(head, args...)

	var stdoutBuf, stderrBuf bytes.Buffer
	cmd.Stdout = io.MultiWriter(os.Stdout, &stdoutBuf)
	cmd.Stderr = io.MultiWriter(os.Stderr, &stderrBuf)

	err = cmd.Run()
	if err != nil {
		log.Fatalf("cmd.Run() failed with %s\n", err)
	}
	return err
}

func setClusterContext() bool {

	validatepath := func(input string) error {
		_, err := os.Stat(input)
		if os.IsNotExist(err) {
			return errors.New("The File does not exist in the given path")
		}
		return nil
	}

	var kubeconfig string
	kubeconfig = enterValue(validatepath, "Please enter the fully qualified path of your kubeconfig file")

	if kubeconfig != "" {
		getcontextcmd := fmt.Sprintf("kubectl config get-contexts --kubeconfig=%s", kubeconfig)
		err := execCommand(getcontextcmd)
		if err == nil {
			context := enterValue(nil, "Please enter the cluster context to be used from the avaliable contexts")
			if context != "" {
				usecontextcmd := fmt.Sprintf("kubectl config use-context %s --kubeconfig=%s", context, kubeconfig)
				err := execCommand(usecontextcmd)
				if err == nil {
					return true
				}
			}
		}
	}
	return false
}

func selectGovServicesToInstall() string {

	var versionfiles []string
	var modules []string
	var selectedMod []string
	svclist := list.New()
	set := NewSet()
	var argStr string = ""
	var releaseChartDir string = "../../config-as-code/product-release-charts/"

	// Get the versions from the chart and display it to user to select
	file, err := os.Open(releaseChartDir)
	if err != nil {
		log.Fatalf("failed opening directory: %s", err)
	}
	defer file.Close()

	prodList, _ := file.Readdirnames(0) // 0 to read all files and folders

	var optedProduct string = ""
	optedProduct, _ = sel(prodList, "Choose the Gov stack services that you would you like to install")

	if optedProduct != "" {
		files, err := ioutil.ReadDir(releaseChartDir + optedProduct)
		if err != nil {
			log.Fatal(err)
		}

		for _, f := range files {
			name := f.Name()
			versionfiles = append(versionfiles, name[s.Index(name, "-")+1:s.Index(name, ".y")])
		}
		var version string = ""
		version, _ = sel(versionfiles, "Which version of the selected product would like to install?")
		if version != "" {
			argFile := releaseChartDir + optedProduct + "/dependancy_chart-" + version + ".yaml"

			// Decode the yaml file and assigning the values to a map
			chartFile, err := ioutil.ReadFile(argFile)
			if err != nil {
				fmt.Println("\n\tERROR: Preparing required services details =>", argFile, err)
				return ""
			}

			// Parse the yaml values
			fullChart := Digit{}
			err = yaml.Unmarshal(chartFile, &fullChart)
			if err != nil {
				fmt.Println("\n\tERROR: Sourcing the the gov services matrix for your requirement => ", argFile, err)
				return ""
			}

			// Mapping the images to servicename
			var m = make(map[string][]string)
			for _, s := range fullChart.Modules {
				m[s.Name] = s.Services
				if strings.Contains(s.Name, "m_") {
					modules = append(modules, s.Name)
				}
			}
			modules = append(modules, "Exit")
			result, err := sel(modules, "Select the DIGIT gov services that you want to install, choose Exit to complete selection")
			//if err == nil {
			for result != "Exit" && err == nil {
				selectedMod = append(selectedMod, result)
				result, err = sel(modules, "Select the modules you want to install, you can select multiple if you wish, choose Exit to complete selection")
			}
			if selectedMod != nil {
				for _, mod := range selectedMod {
					getService(fullChart, mod, *set, svclist)
				}
				for element := svclist.Front(); element != nil; element = element.Next() {
					imglist := m[element.Value.(string)]
					imglistsize := len(imglist)
					for i, service := range imglist {
						argStr = argStr + service
						if !(element.Next() == nil && i == imglistsize-1) {
							argStr = argStr + ","
						}

					}
				}
			}
		}
	}
	return argStr
}

func prepareDeploymentConfig(installType string) string {

	var targetConfig string = ""

	fmt.Sprintf("Now, you need to prepare the deployment configuration for the following infraType that you chose\n\t %s", installType)

	fmt.Sprintf("Prepare deployment configuration eessentially means the following, please read carefully and ensure it is available:\n\n\t 1. You need to specify your URL in which you want to application to be available\n\t 2. Depending the Gov services that you chose, following specific details should be configured\n\t\t\t 1. Notification services like SMS, Email, gateway details for OTPs, Notifications\n\t\t\t 2. Whatsapp Integration configuration for chartBot services\n\t\t\t 3. Payment Gateways if PT, TL services chosen for making the payment transactions\n\t\t\t 4. Google GeoCoding API credentials, for the location services\n\t\t\t 5.Your MDMS and configuration with your tenant and role access details\n\t 3. Your DB details \n\t 4. As per your Infra type and the actual cloud resource provisioning the Disk volumes should be mapped to the stateful services like ElasticService, Kafka, Zookeeper, etc")

	return targetConfig
}

func deployCharts(argStr string, configFile string) {

	var goDeployCmd string = fmt.Sprintf("go run main.go deploy -c -e %s%s", configFile, argStr)
	var previewDeployCmd string = fmt.Sprintf("%s -p", goDeployCmd)

	confirm := []string{"Yes", "No"}
	preview, _ := sel(confirm, "Do you want to preview the k8s manifests before the actual Deployment")
	if preview == "Yes" {
		fmt.Println("That's cool... preview is getting loaded. Please review it and cross check the kubernetes manifests before the deployment")
		err := execCommand(previewDeployCmd)
		if err == nil {
			fmt.Println("You can now start actual deployment")
			err := execCommand(goDeployCmd)
			if err == nil {
				fmt.Println("We are done with the deployment. You can start using the services. Thank You!!!")
				return
			} else {
				fmt.Println("Something went wrong, refer the error\n")
				fmt.Println(err)
			}
			return
		} else {
			fmt.Println("Something went wrong, refer the error\n")
			fmt.Println(err)
		}
	} else {
		consent, _ := sel(confirm, "Are we good to proceed with the actual deployment?")
		if consent == "Yes" {
			fmt.Println("Whola!, That's great... Sit back and wait for the deployment to complete in about 10 min")
			err := execCommand(goDeployCmd)
			if err == nil {
				fmt.Println("We are done with the deployment. You can start using the services. Thank You!!!")
				fmt.Println("Hope I made your life easy with the deployment ... Have a goodd day !!!")
				return
			} else {
				fmt.Println("Something went wrong, refer the error\n")
				fmt.Println(err)
			}
		} else {
			endScript()
		}

	}

}

func execSingleCommand(command string) error {
	var err error

	cmd := exec.Command("sh", "-c", command)

	log.Println(string(Blue), " ==> "+command)

	var stdoutBuf, stderrBuf bytes.Buffer
	cmd.Stdout = io.MultiWriter(os.Stdout, &stdoutBuf)
	cmd.Stderr = io.MultiWriter(os.Stderr, &stderrBuf)

	err = cmd.Run()
	if err != nil {
		log.Fatalf("cmd.Run() failed with %s\n", err)
	}
	return err
}

// Cloud cloudLoginCredentials functions
func awslogin(accessKey string, secretKey string) bool {

	var cloudLoginCredentials bool = false

	if accessKey != "" && secretKey != "" {
		awslogincommand := fmt.Sprintf("aws configure --profile digit-infra-aws set aws_access_key_id \"%s\" && aws configure --profile digit-infra-aws set aws_secret_access_key \"%s\" && aws configure --profile digit-infra-aws set region \"ap-south-1\"", accessKey, secretKey)
		fmt.Println(awslogincommand)
		err := execSingleCommand(awslogincommand)
		if err == nil {
			cloudLoginCredentials = true
		}
	}
	return cloudLoginCredentials
}

func awsloginWithSession(accessKey string, secretKey string, sessionToken string) bool {

	var cloudLoginCredentials bool = false

	if accessKey != "" && secretKey != "" {
		awslogincommand := fmt.Sprintf("aws configure --profile digit-infra-aws set aws_access_key_id \"%s\" && aws configure --profile digit-infra-aws set aws_secret_access_key \"%s\" && aws configure --profile digit-infra-aws set aws_session_token \"%s\"  && aws configure --profile digit-infra-aws set region \"ap-south-1\"", accessKey, secretKey, sessionToken)
		fmt.Println(awslogincommand)
		err := execSingleCommand(awslogincommand)
		if err == nil {
			cloudLoginCredentials = true
		}
	}
	return cloudLoginCredentials
}

func azurelogin(userName string, password string) bool {

	var cloudLoginCredentials bool = false
	if userName != "" && password != "" {
		azurelogincommand := fmt.Sprintf("az cloudLoginCredentials -u %s -p %s", userName, password)
		err := execCommand(azurelogincommand)
		if err == nil {
			cloudLoginCredentials = true
		}
	}
	return cloudLoginCredentials
}

// Input functions

func sel(items []string, label string) (string, error) {
	var result string
	var err error
	prompt := promptui.Select{
		Label: label,
		Items: items,
		Size:  30,
	}
	_, result, err = prompt.Run()

	//if err != nil {
	//	fmt.Printf("Invalid Selection %v\n", err)
	//}
	return result, err
}

func enterValue(validate promptui.ValidateFunc, label string) string {
	var result string
	prompt := promptui.Prompt{
		Label:    label,
		Validate: validate,
	}
	result, _ = prompt.Run()

	//if err != nil {
	//	fmt.Printf("Invalid Selection %v\n", err)
	//}
	return result
}

func addDNS(dnsDomain string, dnsType string, dnsName string, dnsValue string) bool {

	var headers string = "Authorization: sso-key 3mM44UcBKoVvB2_Xspi4jKZqJSQUkdouMV4Ck:3pzZiuUPNxzZKu2FfUD9Sm"

	dnsCommand := fmt.Sprintf("curl -X PATCH \"https://api.godaddy.com/v1/domains/%s/records -H %s -H Content-Type: application/json --data-raw [{\"data\":\"%s\",\"name\":\"%s\",\"type\":\"%s\"}]", dnsDomain, headers, dnsValue, dnsName, dnsType)
	fmt.Println(dnsCommand)
	err := execSingleCommand(dnsCommand)
	if err == nil {
		return true
	} else {
		return false
	}
}

func endScript() {
	fmt.Println("Take your time, You can come back at any time ... Thank for leveraging me :)!!!")
	fmt.Println("Hope I made your life easy with the deployment ... Have a goodd day !!!")
	return
}
