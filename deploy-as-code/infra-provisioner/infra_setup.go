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

	fmt.Println(string(Green), "\n*******  Welcome to DIGIT Server setup & Deployment !!! ******** \n\n Please ensure the Pre-requsites from the below link before you proceed *********\n https://docs.digit.org/Infra-calculator\n")
	//var proceedQuestion string

	infraType := []string{
		"1. Pilot/POC (Just for a POC to Quickstart and explore",
		"2. DevTest Setup (You to setup and build/customize and test",
		"3. Bare Minimal (95% reliability), 10 concurrent gov services per sec",
		"4. Mendium (99.99% reliability), 100 concurrent gov services per sec",
		"5. High (99.99% reliability), 1000 concurrent gov services per sec",
		"6. For custom options, use this calcualtor to determine the required nodes (https://docs.digit.org/Infra-calculator)"}

	var optedInfraType string = ""
	optedInfraType, _ = sel(infraType, "Select the suitable below infra option for your usecase")

	var number_of_worker_nodes int
	switch {
	case optedInfraType == "1. Pilot/POC (Just for a POC where for a Quickstart and explore)":
		number_of_worker_nodes = 1
	case optedInfraType == "2. DevTest Setup (You to setup and build/customize and test":
		number_of_worker_nodes = 2 //TBD
	case optedInfraType == "3. Bare Minimal (95% reliability), 10 concurrent gov services per sec":
		number_of_worker_nodes = 3 //TBD
	case optedInfraType == "4. Mendium (99.99% reliability), 100 concurrent gov services per sec":
		number_of_worker_nodes = 4 //TBD
	case optedInfraType == "5. High (99.99% reliability), 1000 concurrent gov services per sec":
		number_of_worker_nodes = 5 //TBD
	case optedInfraType == "6. For custom options, use this calcualtor to determine the required nodes (https://docs.digit.org/Infra-calculator) ":
		number_of_worker_nodes, _ = strconv.Atoi(enterValue(nil, "How many VM/nodes are required based on the calculation"))
	}

	selectGovServicesToInstall()

	cloudPlatforms := []string{"AWS", "AZURE", "GOOGLE CLOUD (GCP)", "On-prem/Private Cloud"}
	var optedCloud string = ""
	optedCloud, _ = sel(cloudPlatforms, "Choose the cloud type to provision the required servers for the selectdd gov stack services?")

	var login bool = false
	var cloud string = "sample-aws"

	switch {
	case optedCloud == "AWS":
		var optedAccessType string
		var aws_access_key string
		var aws_secret_key string
		var aws_session_key string

		accessTypes := []string{"Root Admin", "Temprory Admin"}
		optedAccessType, _ = sel(accessTypes, "Choose your AWS access type? eg: If your access is session based unlike root admin")

		fmt.Println("\n Great, you need to input your " + optedCloud + "credentials to provision the cloud resources ..\n")
		fmt.Println("Input the AWS access key id\n")
		fmt.Scanln(&aws_access_key)

		fmt.Println("Input the AWS secret key\n")
		fmt.Scanln(&aws_secret_key)

		fmt.Println("Input the AWS Session Token\n")
		fmt.Scanln(&aws_session_key)

		if optedAccessType == "Temprory Admin" {
			login = awsloginWithSession(aws_access_key, aws_secret_key, aws_session_key)
		} else {
			login = awslogin(aws_access_key, aws_secret_key)
		}

	case optedCloud == "AZURE":
		fmt.Println("\n Great, you need to input your " + optedCloud + "credentials to provision the cloud resources ..\n")
		azure_username := enterValue(nil, "Please enter your AZURE UserName")
		azure_password := enterValue(nil, "Enter your AZURE Password")
		login = azurelogin(azure_username, azure_password)

	case optedCloud == "GOOGLE CLOUD (GCP)":
		fmt.Println("\n Great, you need to input your " + optedCloud + "credentials to provision the cloud resources ..\n")
		fmt.Println("Support for the " + optedCloud + "is still underway ... you need to wait")

	case optedCloud == "On-prem/Private Cloud":
		fmt.Println("\n Great, you need to input your " + optedCloud + "credentials to provision the cloud resources ..\n")
		fmt.Println("Support for the " + optedCloud + "is still underway ... you need to wait")

	default:
		//fmt.Println("\n Great, you need to input your " + optedCloud + "credentials to provision the cloud resources ..\n")
		//fmt.Println("Support for the " + optedCloud + "is still underway ... you need to wait")
	}

	if login {
		fmt.Println(string(Green), "\n*******  Let's proceed with cluster creation, please input the requested details below *********\n")
		cluster_name := enterValue(nil, "How do you want to name the Cluster? eg: dev-your-name or org-name")
		s3_bucket_tfstore := cluster_name + "-tf-store-" + strconv.Itoa(rand.Int())
		dir := "DIGIT-DevOps"
		gitCmd := ""
		_, err := os.Stat(dir)
		if os.IsNotExist(err) {
			gitCmd = fmt.Sprintf("git clone -b release-infra-demo https://github.com/egovernments/DIGIT-DevOps.git %s", dir)
		} else {
			gitCmd = fmt.Sprintf("git -C %s pull", dir)
		}
		execCommand(gitCmd)

		//fmt.Println(string(Green), "\n*******  The number of nodes depend on the the following options *********\n")
		//worker_nodes := enterValue(nil, "How many VM/nodes is required")

		//db_name := enterValue(nil, "As part of the DIGIT setup, you need DB to created, what do you want to name the database")

		db_pswd := enterValue(nil, "What should be the database pswd to be created")

		tfInitCmd := fmt.Sprintf("terraform init %s/infra-as-code/terraform/%s/remote-state", dir, cloud)
		execSingleCommand(tfInitCmd)

		tfPlan := fmt.Sprintf("terraform plan -var=\"bucket_name=%s\" %s/infra-as-code/terraform/%s/remote-state", s3_bucket_tfstore, dir, cloud)
		fmt.Println(tfPlan)
		execSingleCommand(tfPlan)

		tfApply := fmt.Sprintf("terraform apply -var=\"bucket_name=%s\" -auto-approve %s/infra-as-code/terraform/%s/remote-state", s3_bucket_tfstore, dir, cloud)
		execSingleCommand(tfApply)

		tfMainInit := fmt.Sprintf("terraform init %s/infra-as-code/terraform/%s", dir, cloud)
		execSingleCommand(tfMainInit)
		tfMainPlan := fmt.Sprintf("terraform plan -var=\"bucket_name=%s\" -var=\"cluster_name=%s\" -var=\"db_password=%s\" -var=\"number_of_worker_nodes=%s\" %s/infra-as-code/terraform/%s", s3_bucket_tfstore, cluster_name, db_pswd, number_of_worker_nodes, dir, cloud)
		fmt.Println()
		fmt.Println(tfMainPlan)
		execSingleCommand(tfMainPlan)
		//tfMainApply := fmt.Sprintf("terraform apply -var=\"bucket_name=%s\" -var=\"cluster_name=%s\" -var=\"db_password=%s\" -var=\"number_of_worker_nodes=%s\" -auto-approve %s/infra-as-code/terraform/%s", s3_bucket_tfstore, cluster_name, db_pswd, worker_nodes, dir, cloud)
		//execCommand(tfMainApply)
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
	//log.Println("Printing full command part", parts)
	//	The first part is the command, the rest are the args:
	head := parts[0]
	args := parts[1:len(parts)]
	//	Format the command
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

func execSingleCommand(command string) error {
	var err error

	cmd := exec.Command("sh", "-c", command)

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
	var contextset bool = false
	var kubeconfig string = ""

	validatepath := func(input string) error {
		_, err := os.Stat(input)
		if os.IsNotExist(err) {
			return errors.New("The File does not exist in the given path")
		}
		return nil
	}

	kubeconfig = enterValue(validatepath, "Please enter the fully qualified path of the kubeconfig file")

	if kubeconfig != "" {
		getcontextcmd := fmt.Sprintf("kubectl config get-contexts --kubeconfig=%s", kubeconfig)
		err := execCommand(getcontextcmd)
		if err == nil {
			context := enterValue(nil, "Please enter the cluster context to be used from the avaliable contexts")
			if context != "" {
				usecontextcmd := fmt.Sprintf("kubectl config use-context %s --kubeconfig=%s", context, kubeconfig)
				err := execCommand(usecontextcmd)
				if err == nil {
					contextset = true
				}
			}
		}
	}
	return contextset
}

func awslogin(accessKey string, secretKey string) bool {

	var login bool = false

	if accessKey != "" && secretKey != "" {
		awslogincommand := fmt.Sprintf("aws configure --profile digit-infra-aws set aws_access_key_id \"%s\" && aws configure set aws_secret_access_key \"%s\" && aws configure set region \"ap-south-1\"", accessKey, secretKey)
		fmt.Println(awslogincommand)
		err := execSingleCommand(awslogincommand)
		if err == nil {
			login = true
		}
	}
	return login
}

func awsloginWithSession(accessKey string, secretKey string, sessionToken string) bool {

	var login bool = false

	if accessKey != "" && secretKey != "" {
		awslogincommand := fmt.Sprintf("aws configure --profile digit-infra-aws set aws_access_key_id \"%s\" && aws configure set aws_secret_access_key \"%s\" && aws configure set aws_session_token \"%s\"  && aws configure set region \"ap-south-1\"", accessKey, secretKey, sessionToken)
		fmt.Println(awslogincommand)
		err := execSingleCommand(awslogincommand)
		if err == nil {
			login = true
		}
	}
	return login
}

func azurelogin(userName string, password string) bool {

	var login bool = false
	if userName != "" && password != "" {
		azurelogincommand := fmt.Sprintf("az login -u %s -p %s", userName, password)
		err := execCommand(azurelogincommand)
		if err == nil {
			login = true
		}
	}
	return login
}

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

func endScript() {
	fmt.Println("Take your time, You can come back at any time ... Thank for leveraging me :)!!!")
	fmt.Println("Hope I made your life easy with the deployment ... Have a goodd day !!!")
	return
}

func selectGovServicesToInstall() {

	var versionfiles []string
	var modules []string
	var selectedMod []string
	svclist := list.New()
	set := NewSet()
	var argStr string = ""

	// Get the versions from the chart and display it to user to select
	file, err := os.Open("../helm/product-release-charts/")
	if err != nil {
		log.Fatalf("failed opening directory: %s", err)
	}
	defer file.Close()

	prodList, _ := file.Readdirnames(0) // 0 to read all files and folders

	var optedProduct string = ""
	optedProduct, _ = sel(prodList, "Choose the Gov stack services that you would you like to install")

	if optedProduct != "" {
		files, err := ioutil.ReadDir("../helm/product-release-charts/" + optedProduct)
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
			argFile := "../helm/product-release-charts/" + optedProduct + "/dependancy_chart-" + version + ".yaml"

			// Decode the yaml file and assigning the values to a map
			chartFile, err := ioutil.ReadFile(argFile)
			if err != nil {
				fmt.Println("\n\tERROR: Preparing required services details =>", argFile, err)
				return
			}

			// Parse the yaml values
			fullChart := Digit{}
			err = yaml.Unmarshal(chartFile, &fullChart)
			if err != nil {
				fmt.Println("\n\tERROR: Sourcing the the gov services matrix for your requirement => ", argFile, err)
				return
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

}

func deployScript(argStr string, envfile string) {

	var envfiles []string
	contextset := setClusterContext()

	if contextset {
		envfilesFromDir, err := ioutil.ReadDir("../helm/environments/")
		if err != nil {
			log.Fatal(err)
		}
		for _, envfile := range envfilesFromDir {
			filename := envfile.Name()
			if !s.Contains(filename, "secrets") {
				envfiles = append(envfiles, filename[0:s.Index(filename, ".yaml")])
			}
		}

		// Choose the env
		var env string = ""
		env, err = sel(envfiles, "Choose the target env for the installation")

		if env != "" {
			var goDeployCmd string
			confirm := []string{"Yes", "No"}

			goDeployCmd = fmt.Sprintf("go run main.go deploy -c -e %s %s", env, argStr)

			preview, _ := sel(confirm, "Do you want to preview the manifests before the actual Deployment")
			if preview == "Yes" {
				goDeployCmd = fmt.Sprintf("%s -p", goDeployCmd)
				fmt.Println("That's cool... The preview is getting loaded. Please review it and decide to proceed with the deployment")
				err := execCommand(goDeployCmd)
				if err == nil {
					fmt.Println("You can now start actual deployment")
					goDeployCmd = fmt.Sprintf("go run main.go deploy -c -e %s %s", env, argStr)
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
				}

			}

		}
	}
}
