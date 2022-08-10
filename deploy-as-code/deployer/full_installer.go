package main

import (
	"bytes"
	"container/list"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"os"
	"os/exec"
	"strconv"
	"strings"

	"github.com/jcelliott/lumber"
	"github.com/manifoldco/promptui"
	"golang.org/x/crypto/ssh"
	yaml "gopkg.in/yaml.v3"

	//"bufio"
	"deployer/configs"
	"encoding/json"
)

var cloudTemplate string // Which terraform template to choose
var repoDirRoot string
var selectedMod []string
var Flag string
var db_pswd string
var sshFile string

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
	var cloudLoginCredentials bool     // Is there a valid cloud account and credentials
	var isProductionSetup bool = false
	var cluster_name string

	infraType := []string{
		"0. You have an existing kubernetes Cluster ready, you would like to leverage it to setup DIGIT on that",
		"1. Pilot/POC (Just for a POC to Quickstart and explore)",
		"2. DevTest Setup (To setup and build/customize and test)",
		"3. Production: Bare Minimal (90% reliability), 10 gov services, 10 concurrent users/sec",
		"4. Production: Medium (95% reliability), 50+ concurrent gov services 100 concurrent users/sec",
		"5. Production: HA/DRS Setup (99.99% reliability), 50+ concurrent gov services 1000 concurrent users/sec",
		"6. For custom options, use this calcualtor to determine the required nodes (https://docs.digit.org/Infra-calculator)"}

	cloudPlatforms := []string{
		"0. Local machine/Your Existing VM",
		"1. AWS-EC2 - Quickstart with a Single EC2 Instace on AWS",
		"2. On-prem/Private Cloud - Quickstart with Single VM",
		"3. AWS-EKS - Production grade Elastic Kubernetes Service (EKS)",
		"4. AZURE-AKS - Production grade Azure Kubernetes Service (AKS)",
		"5. GOOGLE CLOUD - Production grade Google Kubernetes Engine (GKE)",
		"6. On-prem/Privare Cloud - Production grade Kubernetes Cluster Setup"}

	fmt.Println(string(Green), "\n*******  Welcome to DIGIT Server setup & Deployment !!! ******** \n\n *********\n https://docs.digit.org/Infra-calculator\n")
	const sPreReq = "Pre-requsites (Please Read Carefully):\n\tDIGIT comprises of many microservices that are packaged as docker containers that can be run on any container supported platforms like dockercompose, kubernetes, etc. Here we'll have a setup a kubernetes.\nHence the following are mandatory to have it before you proceed.\n\t1. Kubernetes(K8s) Cluster.\n\t\t[Option a] Local/VM: If you do not have k8s, using this link you can create k8s cluster on your local or on a VM.\n\t\t[b] Cloud: If you have your cloud account like AWS, Azure, GCP, SDC or NIC you can follow this link to create k8s.\n\t2. Post the k8s cluster creation you should get the Kubeconfig file, which you have saved in your local machine.\n\t\n\n Well! Let's get started with the DIGIT Setup process, if you want to abort any time press (Ctl+c), you can always come back and rerun the script."
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
			number_of_worker_nodes = 1
		case infraType[3]:
			number_of_worker_nodes = 3 //TBD
			isProductionSetup = true
		case infraType[4]:
			number_of_worker_nodes = 4 //TBD
			isProductionSetup = true
		case infraType[5]:
			number_of_worker_nodes = 5 //TBD
		case infraType[6]:
			number_of_worker_nodes, _ = strconv.Atoi(enterValue(nil, "How many VM/nodes are required based on the calculation"))
			isProductionSetup = true
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

			accessTypes := []string{"Root Admin", "Temprory Admin", "Already configured"}
			optedAccessType, _ = sel(accessTypes, "Choose your AWS access type? eg: If your access is session based unlike root admin")

			fmt.Println("\n Great, you need to input your " + optedCloud + "credentials to provision the cloud resources ..\n")

			if optedAccessType == "Temprory Admin" {

				fmt.Println("Input the AWS access key id")
				fmt.Scanln(&aws_access_key)

				fmt.Println("\nInput the AWS secret key")
				fmt.Scanln(&aws_secret_key)

				fmt.Println("\nInput the AWS Session Token")
				fmt.Scanln(&aws_session_key)

				cloudLoginCredentials = awslogin(aws_access_key, aws_secret_key, aws_session_key, "")
			} else if optedAccessType == "Root Admin" {

				fmt.Println("Input the AWS access key id")
				fmt.Scanln(&aws_access_key)

				fmt.Println("\nInput the AWS secret key")
				fmt.Scanln(&aws_secret_key)

				cloudLoginCredentials = awslogin(aws_access_key, aws_secret_key, "", "")
			} else {
				cloudLoginCredentials = awslogin("", "", "", "")
				fmt.Println("Proceeding with the existing AWS profile configured")
			}
		case cloudPlatforms[2]:
			//TBD

		case cloudPlatforms[3]:
			var optedAccessType string
			var aws_access_key string
			var aws_secret_key string
			var aws_session_key string
			Flag = "aws"
			cloudTemplate = "sample-aws"

			accessTypes := []string{"Root Admin", "Temprory Admin", "Already configured"}
			optedAccessType, _ = sel(accessTypes, "Choose your AWS access type? eg: If your access is session based unlike root admin")

			fmt.Println("\n Great, you need to input your " + optedCloud + "credentials to provision the cloud resources ..\n")

			if optedAccessType == "Temprory Admin" {

				fmt.Println("Input the AWS access key id")
				fmt.Scanln(&aws_access_key)

				fmt.Println("\nInput the AWS secret key")
				fmt.Scanln(&aws_secret_key)

				fmt.Println("\nInput the AWS Session Token")
				fmt.Scanln(&aws_session_key)

				cloudLoginCredentials = awslogin(aws_access_key, aws_secret_key, aws_session_key, "")
			} else if optedAccessType == "Root Admin" {

				fmt.Println("Input the AWS access key id")
				fmt.Scanln(&aws_access_key)

				fmt.Println("\nInput the AWS secret key")
				fmt.Scanln(&aws_secret_key)

				cloudLoginCredentials = awslogin(aws_access_key, aws_secret_key, "", "")
			} else {
				cloudLoginCredentials = awslogin("", "", "", "")
				fmt.Println("Proceeding with the existing AWS profile configured")
			}

		case cloudPlatforms[4]:
			cloudTemplate = "sample-azure"
			fmt.Println("\n Great, you need to input your " + optedCloud + "credentials to provision the cloud resources ..\n")
			azure_username := enterValue(nil, "Please enter your AZURE UserName")
			azure_password := enterValue(nil, "Enter your AZURE Password")
			cloudLoginCredentials = azurelogin(azure_username, azure_password)

		case cloudPlatforms[5]:
			cloudTemplate = "sample-gcp"
			fmt.Println("\n Great, you need to input your " + optedCloud + "credentials to provision the cloud resources ..\n")
			fmt.Println("Support for the " + optedCloud + "is still underway ... you need to wait")

		case cloudPlatforms[6]:
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
		fmt.Println(string(Green), "Make sure that the cluster name is unique if you are trying consecutively, duplicate DNS/hosts file entry under digit.org domain could have been mapped already\n")

		cluster_name = enterValue(nil, "How do you want to name the Cluster? eg: your-name_dev or your-name_poc")

		// fmt.Println("How do you want to name the Cluster? \n eg: your-name_dev or your-name_poc")
		// fmt.Scanln(&cluster_name)

		repoDirRoot = "DIGIT-DevOps"
		gitCmd := ""
		_, err := os.Stat(repoDirRoot)
		if os.IsNotExist(err) {
			gitCmd = fmt.Sprintf("git clone -b release https://github.com/egovernments/DIGIT-DevOps.git %s", repoDirRoot)
		} else {
			gitCmd = fmt.Sprintf("git -C %s pull", repoDirRoot)
		}
		execCommand(gitCmd)

		if !isProductionSetup {

			sshFile = "./digit-ssh.pem"
			var keyName string = "digit-aws-vm"
			pubKey, _, err := GetKeyPair(sshFile)
			// to pick public ip and private ip from terraform state

			if err != nil {
				log.Fatalf("Failed to generate SSH Key %s\n", err)
			} else {
				execSingleCommand(fmt.Sprintf("terraform -chdir=%s/infra-as-code/terraform/%s init", repoDirRoot, cloudTemplate))

				execSingleCommand(fmt.Sprintf("terraform -chdir=%s/infra-as-code/terraform/%s plan -var=\"public_key=%s\" -var=\"key_name=%s\"", repoDirRoot, cloudTemplate, pubKey, keyName))

				execSingleCommand(fmt.Sprintf("terraform  -chdir=%s/infra-as-code/terraform/%s apply -auto-approve -var=\"public_key=%s\" -var=\"key_name=%s\"", repoDirRoot, cloudTemplate, pubKey, keyName))
				//taking public ip and private ip from terraform.tfstate
				quickState, err := ioutil.ReadFile("DIGIT-DevOps/infra-as-code/terraform/quickstart-aws-ec2/terraform.tfstate")
				if err != nil {
					log.Printf("%v", err)
				}
				var quick configs.Quickstart
				err = json.Unmarshal(quickState, &quick)
				//publicip
				ip := quick.Outputs.PublicIP.Value
				//privateip
				privateip := quick.Resources[0].Instances[0].Attributes.PrivateIP
				createK3d(cluster_name, ip, keyName, privateip)
				changePrivateIp(cluster_name, privateip)

			}

		} else {
			db_pswd = enterValue(nil, "What should be the database password to be created, it should be 8 char min")
			execSingleCommand(fmt.Sprintf("terraform -chdir=%s/infra-as-code/terraform/%s init", repoDirRoot, cloudTemplate))

			execSingleCommand(fmt.Sprintf("terraform -chdir=%s/infra-as-code/terraform/%s plan -var=\"cluster_name=%s\" -var=\"db_password=%s\" -var=\"number_of_worker_nodes=%d\"", repoDirRoot, cloudTemplate, cluster_name, db_pswd, number_of_worker_nodes))

			execSingleCommand(fmt.Sprintf("terraform -chdir=%s/infra-as-code/terraform/%s apply -auto-approve -var=\"cluster_name=%s\" -var=\"db_password=%s\" -var=\"number_of_worker_nodes=%d\"", repoDirRoot, cloudTemplate, cluster_name, db_pswd, number_of_worker_nodes))

			//calling funtion to write config file
			Configsfile()

		}
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

// create a cluster in vm
func createK3d(clusterName string, publicIp string, keyName string, privateIp string) {
	commands := []string{
		"mkdir ~/kube && sudo chmod 777 ~/kube",
		"sudo k3d kubeconfig get k3s-default > " + clusterName + "_k3dconfig",
	}
	createClusterCmd := fmt.Sprintf("sudo k3d cluster create --api-port %s:6550 --k3s-server-arg --no-deploy=traefik --agents 2 -v /home/ubuntu/kube:/kube@agent[0,1] -v /home/ubuntu/kube:/kube@server[0] --port 8333:9000@loadbalancer --k3s-server-arg --tls-san=%s", privateIp, publicIp)
	command := fmt.Sprintf("%s&&%s&&%s", commands[0], createClusterCmd, commands[1])
	execRemoteCommand("ubuntu", publicIp, sshFile, command)
	copyConfig := fmt.Sprintf("scp ubuntu@%s:%s_k3dconfig  .", publicIp, clusterName)
	execCommand(copyConfig)
}

//changes the private ip in k3dconfig
func changePrivateIp(clusterName string, privateIp string) {
	path := fmt.Sprintf("%s_k3dconfig", clusterName)
	file, err := ioutil.ReadFile(path)
	if err != nil {
		log.Printf("%v", err)
	}
	var con configs.Config
	err = yaml.Unmarshal(file, &con)
	if err != nil {
		log.Printf("%v", err)
	}
	server := fmt.Sprintf("https://%s:6550", privateIp)
	con.Clusters[0].Cluster.Server = server
	newfile, err := yaml.Marshal(&con)
	if err != nil {
		log.Printf("%v", err)

	}
	err = ioutil.WriteFile("new_k3dconfig", newfile, 0644)
	if err != nil {
		log.Printf("%v", err)
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
			versionfiles = append(versionfiles, name[strings.Index(name, "-")+1:strings.Index(name, ".y")])
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
			result, err := sel(modules, "Select the DIGIT's Gov services that you want to install, choose Exit to complete selection")
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

	var goDeployCmd string = fmt.Sprintf("go run main.go deploy -c -e %s %s", configFile, argStr)
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

func execRemoteCommand(user string, ip string, sshFileLocation string, command string) error {
	var err error
	sshPreFix := fmt.Sprintf("ssh %s@%s -i %s \"%s\" ", user, ip, sshFileLocation, command)

	cmd := exec.Command("sh", "-c", sshPreFix)

	log.Println(string(Blue), " ==> "+sshPreFix)

	var stdoutBuf, stderrBuf bytes.Buffer
	cmd.Stdout = io.MultiWriter(os.Stdout, &stdoutBuf)
	cmd.Stderr = io.MultiWriter(os.Stderr, &stderrBuf)

	err = cmd.Run()
	if err != nil {
		log.Fatalf("cmd.Run() failed with %s\n", err)
	}
	return err
}

// func remoteScpFile(host string, username string, sshKeyPath string, remoteFilePath string, localFilePath string) (success bool) {
// 	// Use SSH key authentication from the auth package
// 	// we ignore the host key in this example, please change this if you use this library

// 	ssh := chilkat.NewSsh()

// 	// Hostname may be an IP address or hostname:
// 	hostname := "www.some-ssh-server.com"
// 	port := 22

// 	puttyKey := chilkat.NewSshKey()
// 	ppkText := puttyKey.LoadText(sshKeyPath)

// 	success := puttyKey.FromPuttyPrivateKey(*ppkText)
// 	if success != true {
// 		fmt.Println(puttyKey.LastErrorText())
// 		ssh.DisposeSsh()
// 		puttyKey.DisposeSshKey()
// 		return false
// 	}

// 	// Connect to an SSH server:
// 	success := ssh.Connect(hostname, port)
// 	if success != true {
// 		fmt.Println(ssh.LastErrorText())
// 		ssh.DisposeSsh()
// 		return false
// 	}

// 	// Wait a max of 5 seconds when reading responses..
// 	ssh.SetIdleTimeoutMs(5000)

// 	// Authenticate using login/password:
// 	success = ssh.AuthenticatePk("myLogin", puttyKey)
// 	if success != true {
// 		fmt.Println(ssh.LastErrorText())
// 		ssh.DisposeSsh()
// 		return false
// 	}

// 	// Once the SSH object is connected and authenticated, we use it
// 	// in our SCP object.
// 	scp := chilkat.NewScp()

// 	success = scp.UseSsh(ssh)
// 	if success != true {
// 		fmt.Println(scp.LastErrorText())
// 		ssh.DisposeSsh()
// 		scp.DisposeScp()
// 		return false
// 	}

// 	success = scp.DownloadFile(remoteFilePath, localFilePath)
// 	if success != true {
// 		fmt.Println(scp.LastErrorText())
// 		ssh.DisposeSsh()
// 		scp.DisposeScp()
// 		return false
// 	}

// 	fmt.Println("SCP download file success.")

// 	// Disconnect
// 	ssh.Disconnect()

// 	ssh.DisposeSsh()
// 	scp.DisposeScp()

// 	return true

// }

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
func awslogin(accessKey string, secretKey string, sessionToken string, profile string) bool {

	var cloudLoginCredentials bool = false
	var awslogincommand string = ""

	if accessKey != "" && secretKey != "" && sessionToken == "" {
		awslogincommand = fmt.Sprintf("aws configure --profile digit-infra-aws set aws_access_key_id \"%s\" && aws configure --profile digit-infra-aws set aws_secret_access_key \"%s\" && aws configure --profile digit-infra-aws set region \"ap-south-1\"", accessKey, secretKey)
	} else if sessionToken != "" {
		awslogincommand = fmt.Sprintf("aws configure --profile digit-infra-aws set aws_access_key_id \"%s\" && aws configure --profile digit-infra-aws set aws_secret_access_key \"%s\" && aws configure --profile digit-infra-aws set aws_session_token \"%s\"  && aws configure --profile digit-infra-aws set region \"ap-south-1\"", accessKey, secretKey, sessionToken)
	} else {
		awsProf := ""
		profile := ""
		awsProf = fmt.Sprintf("aws configure list-profiles")
		out, err := execCommandWithOutput(awsProf)
		if err != nil {
			log.Printf("%s", err)
		}
		profList := strings.Fields(out)
		profile, _ = sel(profList, "choose the profile with right access")
		awslogincommand = fmt.Sprintf("aws configure --profile %s set region \"ap-south-1\"", profile)
		// execCommand(fmt.Sprintf("aws configure list"))

	}

	log.Println(awslogincommand)
	err := execSingleCommand(awslogincommand)
	if err == nil {
		cloudLoginCredentials = true
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

func GetKeyPair(file string) (string, string, error) {
	// read keys from file
	_, err := os.Stat(file)
	if err == nil {
		priv, err := ioutil.ReadFile(file)
		if err != nil {
			lumber.Debug("Failed to read file - %s", err)
			goto genKeys
		}
		pub, err := ioutil.ReadFile(file + ".pub")
		if err != nil {
			lumber.Debug("Failed to read pub file - %s", err)
			goto genKeys
		}
		return string(pub), string(priv), nil
	}

	// generate keys and save to file
genKeys:
	pub, priv, err := GenKeyPair()
	err = ioutil.WriteFile(file, []byte(priv), 0600)
	if err != nil {
		return "", "", fmt.Errorf("Failed to write file - %s", err)
	}
	err = ioutil.WriteFile(file+".pub", []byte(pub), 0644)
	if err != nil {
		return "", "", fmt.Errorf("Failed to write pub file - %s", err)
	}

	return pub, priv, nil
}

func GenKeyPair() (string, string, error) {
	privateKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return "", "", err
	}

	privateKeyPEM := &pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(privateKey)}
	var private bytes.Buffer
	if err := pem.Encode(&private, privateKeyPEM); err != nil {
		return "", "", err
	}

	// generate public key
	pub, err := ssh.NewPublicKey(&privateKey.PublicKey)
	if err != nil {
		return "", "", err
	}

	public := ssh.MarshalAuthorizedKey(pub)
	return string(public), private.String(), nil
}

// below function can be used to store output of command to variable
func execCommandWithOutput(command string) (string, error) {

	parts := strings.Fields(command)
	//	The first part is the command, the rest are the args:
	head := parts[0]
	args := parts[1:len(parts)]
	//	Format the command

	log.Println(string(Blue), " ==> "+command)
	cmd := exec.Command(head, args...)
	out, err := cmd.Output()
	var stdoutBuf, stderrBuf bytes.Buffer
	cmd.Stdout = io.MultiWriter(os.Stdout, &stdoutBuf)
	cmd.Stderr = io.MultiWriter(os.Stderr, &stderrBuf)
	if err != nil {
		log.Fatalf("%s", err)
	}
	return string(out), err
}

// write configs to environment file
func Configsfile() {
	Confirm := []string{"Yes", "No"}
	var out configs.Output
	State, err := ioutil.ReadFile("DIGIT-DevOps/infra-as-code/terraform/sample-aws/terraform.tfstate")
	if err != nil {
		log.Printf("%v", err)
	}
	err = json.Unmarshal(State, &out)
	Config := make(map[string]interface{})
	Domain := enterValue(nil, "Enter a valid Domain name:")
	BranchName := enterValue(nil, "Enter Branch name:")
	DbName := enterValue(nil, "Enter db_name:")
	Kvids := out.Outputs.KafkaVolIds.Value
	Zvids := out.Outputs.ZookeeperVolumeIds.Value
	Esdids := out.Outputs.EsDataVolumeIds.Value
	Esmvids := out.Outputs.EsMasterVolumeIds.Value
	Config["Domain"] = Domain
	Config["BranchName"] = BranchName
	Config["db-host"] = out.Outputs.DbInstanceEndpoint
	Config["db_name"] = DbName
	smsproceed, _ := sel(Confirm, "Do You have your sms Gateway?")
	if smsproceed == "Yes" {
		SmsUrl := enterValue(nil, "Enter your SMS provider url")
		SmsGateway := enterValue(nil, "Enter your SMS Gateway")
		SmsSender := enterValue(nil, "Enter your SMS sender")
		Config["sms-provider-url"] = SmsUrl
		Config["sms-gateway-to-use"] = SmsGateway
		Config["sms-sender"] = SmsSender
	}
	fileproceed, _ := sel(Confirm, "Do You need filestore?")
	if fileproceed == "Yes" {
		if Flag == "aws" {
			bucket := enterValue(nil, "Enter the filestore bucket name:")
			Config["fixed-bucket"] = bucket
		}
		if Flag == "sdc" {
			bucket := enterValue(nil, "Enter the filestore bucket name:")
			Config["fixed-bucket"] = bucket
		}
	}
	botproceed, _ := sel(Confirm, "Do You need chatbot?")
	//write chatbot
	configs.DeployConfig(Config, Kvids, Zvids, Esdids, Esmvids, selectedMod, smsproceed, fileproceed, botproceed, Flag)
}
func endScript() {
	fmt.Println("Take your time, You can come back at any time ... Thank for leveraging me :)!!!")
	fmt.Println("Hope I made your life easy with the deployment ... Have a good day !!!")
	return
}
