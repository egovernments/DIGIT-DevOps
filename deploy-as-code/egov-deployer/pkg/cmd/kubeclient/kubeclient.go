package kubeclient

import (
	"flag"
	"fmt"
	"path/filepath"
	"runtime"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/client-go/util/homedir"
)

func add(x, y int) (z int) {
	z = x + y
	return
}

// Main entrypoint
func Main() {
	var i, j = 100, "helo"
	fmt.Println(i, j)
	for i := 0; i < 10; i++ {
		z := add(434, i)
		fmt.Println(z)
	}
	fmt.Println("counting")

	fmt.Println("done")

	fmt.Print("Go runs on ")
	switch os := runtime.GOOS; os {
	case "darwin":
		fmt.Println("OS X.")
	case "linux":
		fmt.Println("Linux.")
	default:
		// freebsd, openbsd,
		// plan9, windows...
		fmt.Printf("%s.\n", os)
	}

	var kubeconfig *string
	if home := homedir.HomeDir(); home != "" {
		kubeconfig = flag.String("kubeconfig", filepath.Join(home, ".kube", "config"), "(optional) absolute path to the kubeconfig file")
	} else {
		kubeconfig = flag.String("kubeconfig", "", "absolute path to the kubeconfig file")
	}
	flag.Parse()

	config, err := clientcmd.BuildConfigFromFlags("", *kubeconfig)
	if err != nil {
		panic(err)
	}
	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		panic(err)
	}

	deploymentsClient := clientset.AppsV1().Deployments("egov")

	// List Deployments
	fmt.Printf("Listing deployments in namespace %q:\n", "egov")
	list, err := deploymentsClient.List(metav1.ListOptions{})
	if err != nil {
		panic(err)
	}
	for _, d := range list.Items {

		for _, c := range d.Spec.Template.Spec.Containers {
			// fmt.Printf(" * %s \n", c.Image)
			if c.LivenessProbe == nil {
				fmt.Printf(" * %s \n", d.Name)
			} else {
				fmt.Printf(" * %s \n", c.LivenessProbe.HTTPGet.Path)
			}
		}
	}
}
