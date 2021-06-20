package main

import (
	"bytes"
	"container/list"
	"errors"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"os"
	"os/exec"
	"strings"
	s "strings"

	"github.com/manifoldco/promptui"
	"gopkg.in/yaml.v2"
)

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
	var versionfiles []string
	var envfiles []string
	var modules []string
	var selectedMod []string
	svclist := list.New()
	set := NewSet()
	var argStr string = ""

	fmt.Println("\n*******  Welcome to DIGIT INSTALLATION!!! Please ensure the Pre-requsites before you proceed *********\n")
	const sPreReq = "\bPre-requsites (Please Read Carefully):\n\tDIGIT Platform is a combination of multiple microservices that are packaged as docker containers that can be run on any supported infra like dockercompose, kubernetes, etc. Here we'll have a setup baselined for kubernetes.\nHence the following are mandatory to have it before you proceed.\n\t1. Kubernetes(K8s) Cluster.\n\t\t[a] Local: If you do not have k8s, using this link you can create k8s cluster on your local or on a VM.\n\t\t[b] Cloud: If you have your cloud account like AWS, Azure, GCP, SDC or NIC you can follow this link to create k8s.\n\t2. Post the k8s cluster creation you should get the Kubeconfig file, which you have saved in your local machine.\n\t3. Helm installed on your local, follow this link to install\n\t4. Target Env Deployment config file, refer here for the sample template and fill your env specific values.\n\t5. If you want to use encrypted values instead of plain-text for your sensitive configuration, install sops by using this link.\n\nWell! We are good to get started when all the above pre-requistes are met, if not abort it here (Ctl+c) set-it up, come back and rerun the script."
	// Get the Proceedual of the user
	fmt.Println(sPreReq)
	//var proceedQuestion string
	preReqConfirm := []string{"Yes", "No"}

	proceed := sel(preReqConfirm, "Are you good to proceed?")
	if proceed == "Yes" {
		// proceedQuestion = fmt.Sprintf("%s -p", proceedQuestion)
		// execCommand(proceedQuestion)
		setClusterContext()
	} else {
		fmt.Println("That's great too ... Take your time")
		return
	}

	// Get the versions from the chart and display it to user to select
	files, err := ioutil.ReadDir("../helm/digit-release-versions/")
	if err != nil {
		log.Fatal(err)
	}
	for _, f := range files {
		name := f.Name()
		versionfiles = append(versionfiles, name[s.Index(name, "-v")+1:s.Index(name, ".y")])
	}
	version := sel(versionfiles, "Which DIGIT Version You would like to install, Select below")
	argFile := "../helm/digit-release-versions/digit_dependancy_chart-" + version + ".yaml"

	// Decode the yaml file and assigning the values to a map
	chartFile, err := ioutil.ReadFile(argFile)
	if err != nil {
		fmt.Println("\n\tERROR: Reading file =>", argFile, err)
		return
	}

	// Parse the yaml values
	fullChart := Digit{}
	err = yaml.Unmarshal(chartFile, &fullChart)
	if err != nil {
		fmt.Println("\n\tERROR: Parsing => ", argFile, err)
		return
	}

	// Mapping the images to servicename
	var m = make(map[string][]string)
	for _, s := range fullChart.Modules {
		m[s.Name] = s.Services
		modules = append(modules, s.Name)
	}
	modules = append(modules, "Exit")
	result := sel(modules, "Select the DIGIT modules that you want to install, choose Exit to complete selection")
	for result != "Exit" {
		selectedMod = append(selectedMod, result)
		result = sel(modules, "Select the modules you want to install, choose Exit to complete selection")
	}

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
	env := sel(envfiles, "Choose the target env files that are identified from your local configs")
	fmt.Print("")
	var goDeployCmd string
	confirm := []string{"Yes", "No"}

	clusterConf := sel(confirm, "Are we good to proceed generating k8s Deployment manifests for the chosen DIGIT Modules?")
	if clusterConf == "Yes" {
		goDeployCmd = fmt.Sprintf("go run main.go deploy -c -e %s %s", env, argStr)
	} else {
		goDeployCmd = fmt.Sprintf("go run main.go deploy -e %s %s", env, argStr)
	}
	preview := sel(confirm, "Do you want to preview the manifests before the actual Deployment")
	if preview == "Yes" {
		goDeployCmd = fmt.Sprintf("%s -p", goDeployCmd)
		execCommand(goDeployCmd)
	}
	consent := sel(confirm, "Are we good to proceed with the actual deployment?")
	if consent == "Yes" {
		fmt.Println("Whola!, That's great... Sit back and wait for the deployment to complete in about 10 min")
		execCommand(goDeployCmd)
	} else {
		fmt.Println("That's great too ... Take your time")
	}
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

func setClusterContext() {
	validatepath := func(input string) error {
		_, err := os.Stat(input)
		if os.IsNotExist(err) {
			return errors.New("File does not exist")
		}
		return nil
	}

	kubeconfig := enterValue(validatepath, "Please enter the fully qualified path of the kubeconfig file")
	getcontextcmd := fmt.Sprintf("kubectl config get-contexts --kubeconfig=%s", kubeconfig)

	execCommand(getcontextcmd)
	context := enterValue(nil, "Please enter the cluster context to be used from the avaliable contexts")
	usecontextcmd := fmt.Sprintf("kubectl config use-context %s --kubeconfig=%s", context, kubeconfig)
	execCommand(usecontextcmd)
}

func usecontext(kubeconfig string) {
	validatecontext := func(context string) error {
		fmt.Println(context)
		usecontextcmd := fmt.Sprintf("kubectl config use-context %s --kubeconfig=%s", context, kubeconfig)
		return execCommand(usecontextcmd)
	}
	enterValue(validatecontext, "Please confirm the cluster context from the selected kubeconfig")
}

func sel(items []string, label string) string {
	var result string
	var err error
	prompt := promptui.Select{
		Label: label,
		Items: items,
		Size:  10,
	}
	_, result, err = prompt.Run()

	if err != nil {
		fmt.Printf("Prompt failed %v\n", err)
	}
	return result
}

func enterValue(validate promptui.ValidateFunc, label string) string {
	var result string
	prompt := promptui.Prompt{
		Label:    label,
		Validate: validate,
	}
	result, err := prompt.Run()

	if err != nil {
		fmt.Printf("Prompt failed %v\n", err)
	}
	return result
}
