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

	fmt.Println("Welcome to DIGIT DEPLOYMENT!!!")

	setClusterContext()

	files, err := ioutil.ReadDir("../helm/digit-release-versions/")
	if err != nil {
		log.Fatal(err)
	}
	for _, f := range files {
		name := f.Name()
		versionfiles = append(versionfiles, name[s.Index(name, "-v")+1:s.Index(name, ".y")])
	}
	version := sel(versionfiles, "Select the Version You would like to install")
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
	result := sel(modules, "Select the modules you want to install, choose Exit to complete selection")
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

	env := sel(envfiles, "Select the environment you want to install the Modules")
	fmt.Print("")
	var goDeployCmd string
	confirm := []string{"Yes", "No"}

	clusterConf := sel(confirm, "Do you want to install the cluster configs?")
	if clusterConf == "Yes" {
		goDeployCmd = fmt.Sprintf("go run main.go deploy -c -e %s %s", env, argStr)
	} else {
		goDeployCmd = fmt.Sprintf("go run main.go deploy -e %s %s", env, argStr)
	}
	preview := sel(confirm, "Do you want to preview the installation manifests?")
	if preview == "Yes" {
		goDeployCmd = fmt.Sprintf("%s -p", goDeployCmd)
		execCommand(goDeployCmd)
	}
	consent := sel(confirm, "Please provide you consent to proceed with the installation?")
	if consent == "Yes" {
		execCommand(goDeployCmd)
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

	enterValue(validatecontext, "Please the cluster context")
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
