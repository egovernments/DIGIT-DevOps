package main

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"gopkg.in/yaml.v3"
)

// SOPS key types, as named in the sops: block of an encrypted file.
const (
	sopsAge     = "age"
	sopsKMS     = "kms"
	sopsAzureKV = "azure_kv"
)

var sopsKeyTypes = []string{sopsAge, sopsKMS, sopsAzureKV, "gcp_kms", "hc_vault", "pgp"}

// sopsMethods lists the key types a SOPS file is encrypted to. sops writes
// every key type into the metadata, so only the non-empty ones count.
func sopsMethods(data []byte) ([]string, error) {
	var doc struct {
		Sops map[string]any `yaml:"sops"`
	}
	if err := yaml.Unmarshal(data, &doc); err != nil {
		return nil, fmt.Errorf("not valid YAML: %w", err)
	}
	if doc.Sops == nil {
		return nil, fmt.Errorf("no sops: metadata block, so it is not SOPS-encrypted")
	}
	var methods []string
	for _, k := range sopsKeyTypes {
		if list, ok := doc.Sops[k].([]any); ok && len(list) > 0 {
			methods = append(methods, k)
		}
	}
	if len(methods) == 0 {
		return nil, fmt.Errorf("the sops: block names no keys")
	}
	return methods, nil
}

// checkDeclaredMethod makes sure the secrets file really is encrypted with
// the method the config file declares.
func checkDeclaredMethod(declared string, methods []string) error {
	if slices.Contains(methods, declared) {
		return nil
	}
	return fmt.Errorf("the config file says secrets.method is %s, but the file is encrypted with %s",
		declared, strings.Join(methods, ", "))
}

func (w *Workflow) secretsFile() string {
	return filepath.Join(w.repoRoot, "deploy-as-code", "helm", "environments", w.cfg.Env+"-secrets.yaml")
}

// checkSecrets proves the secrets file can be decrypted with what this run
// has, before anything is deployed. The decrypted output is discarded.
func (w *Workflow) checkSecrets(ctx context.Context) error {
	w.log.Step("Checking the SOPS secrets file")
	file := w.secretsFile()
	data, err := os.ReadFile(file)
	if err != nil {
		return stepErr("preflight", "check --env, or ask the SaaS admin for "+filepath.Base(file),
			fmt.Errorf("secrets file: %w", err))
	}
	methods, err := sopsMethods(data)
	if err != nil {
		return stepErr("preflight", "", fmt.Errorf("%s: %w", filepath.Base(file), err))
	}

	method := w.cfg.SecretsMethod
	if err := checkDeclaredMethod(method, methods); err != nil {
		return stepErr("preflight", "fix secrets.method in the config file", fmt.Errorf("%s: %w", filepath.Base(file), err))
	}
	w.secretsMethod = method

	hint := ""
	switch method {
	case sopsAge:
		key := w.cfg.AgeKey
		st, err := os.Stat(key)
		if err != nil {
			return stepErr("preflight", "set secrets.ageKeyFile to the private age key", fmt.Errorf("age key: %w", err))
		}
		if st.Mode().Perm()&0o077 != 0 {
			w.log.Warnf("%s is readable by other users; run: chmod 600 %s", key, key)
		}
		w.run.Setenv("SOPS_AGE_KEY_FILE", key)
		hint = "compare `grep recipient: " + file + "` with `age-keygen -y " + key + "`"
	case sopsKMS:
		w.run.Setenv("AWS_PROFILE", w.cfg.AWSProfile)
		hint = "your AWS identity needs kms:Decrypt on the key in the file's sops: block (`aws sts get-caller-identity`)"
	case sopsAzureKV:
		hint = "`az login` with an identity that has decrypt access to the Key Vault key in the file's sops: block"
	}
	if _, err := w.run.Output(ctx, "sops", "-d", file); err != nil {
		if ctx.Err() != nil {
			return err
		}
		return stepErr("preflight", hint, fmt.Errorf("cannot decrypt %s with %s: %w", filepath.Base(file), method, err))
	}
	w.log.Successf("%s decrypts with %s.", filepath.Base(file), method)
	return w.checkArgoCDDecryption(methods)
}

// argoCDValuesFile is the overlay the deployer appends to the argo-cd chart
// (deployer.go: <chart-dir>/<chart>-values.yaml). It is the only extra values
// file the deployer loads, so the branch's secrets wiring must live there or
// in the chart's values.yaml.
func (w *Workflow) argoCDValuesFile() string {
	return filepath.Join(w.argoCDChartDir(), "argo-cd-values.yaml")
}

func (w *Workflow) argoCDChartDir() string {
	return filepath.Join(w.repoRoot, "deploy-as-code", "helm", "charts", "backbone-services", "argo-cd")
}

// argoCDWiring reports how the branch's Argo CD values let argocd-repo-server
// decrypt secrets.
type argoCDWiring struct {
	mountsAgeKey   bool // argo-cd-values.yaml mounts the sops-age Secret
	azureIdentity  bool // argo-cd-values.yaml sets a Workload Identity client-id
	awsRoleWiredIn bool // values.yaml or argo-cd-values.yaml sets an AWS role
}

func readArgoCDWiring(overlay, base []byte) argoCDWiring {
	return argoCDWiring{
		mountsAgeKey:  bytes.Contains(overlay, []byte("sops-age")),
		azureIdentity: bytes.Contains(overlay, []byte("azure.workload.identity/client-id")),
		awsRoleWiredIn: bytes.Contains(overlay, []byte("AWS_ROLE_ARN")) || bytes.Contains(base, []byte("AWS_ROLE_ARN")) ||
			bytes.Contains(overlay, []byte("eks.amazonaws.com/role-arn")),
	}
}

// argoCDDecryptionProblem says why Argo CD could not decrypt secrets of the
// given method with this wiring, and what to change. Empty means it can.
func argoCDDecryptionProblem(method string, methods []string, wiring argoCDWiring) (problem, hint string) {
	switch {
	case method == sopsAge && !wiring.mountsAgeKey:
		return "the secrets are age-encrypted, but Argo CD on this branch does not mount the sops-age Secret",
			"copy deploy-as-code/helm/charts/backbone-services/argo-cd/argo-cd-values.yaml from the k3s-deployment branch"
	case method != sopsAge && wiring.mountsAgeKey && !slices.Contains(methods, sopsAge):
		return fmt.Sprintf("the secrets use %s, but argo-cd-values.yaml makes Argo CD expect an age key", method),
			"replace argo-cd-values.yaml on this branch with the wiring for " + method + " (README: Part 2, step 4)"
	case method == sopsAzureKV && !wiring.azureIdentity:
		return "the secrets use Azure Key Vault, but argo-cd-values.yaml gives argocd-repo-server no Workload Identity",
			"copy values-azure-keyvault-sops.yaml to argo-cd-values.yaml and set your managed identity's client-id and tenant-id (README: Part 2, step 4)"
	case method == sopsKMS && !wiring.awsRoleWiredIn:
		return "the secrets use AWS KMS, but the Argo CD values set no AWS role for argocd-repo-server",
			"set AWS_ROLE_ARN / AWS_REGION in the repoServer env of the argo-cd values (README: Part 2, step 4)"
	}
	return "", ""
}

// checkArgoCDDecryption stops a run whose Argo CD setup cannot decrypt the
// secrets: it would install fine and then fail every sync.
func (w *Workflow) checkArgoCDDecryption(methods []string) error {
	overlay, _ := os.ReadFile(w.argoCDValuesFile())
	base, _ := os.ReadFile(filepath.Join(w.argoCDChartDir(), "values.yaml"))
	if problem, hint := argoCDDecryptionProblem(w.secretsMethod, methods, readArgoCDWiring(overlay, base)); problem != "" {
		return stepErr("preflight", hint, errors.New(problem))
	}
	return nil
}

// checkRepoServerIdentity shows which cloud identity the installed Argo CD
// decrypts KMS or Key Vault secrets with, so a role copied from another
// environment is noticed. Warning only: Argo CD reports decryption errors
// itself.
func (w *Workflow) checkRepoServerIdentity(ctx context.Context) error {
	var identity string
	switch w.secretsMethod {
	case sopsKMS:
		env, _ := w.kubectl(ctx, "-n", "argocd", "get", "deployment", "argocd-repo-server",
			"-o", `jsonpath={.spec.template.spec.containers[0].env[?(@.name=="AWS_ROLE_ARN")].value}`)
		ann, _ := w.kubectl(ctx, "-n", "argocd", "get", "serviceaccount", "argocd-repo-server",
			"-o", `jsonpath={.metadata.annotations.eks\.amazonaws\.com/role-arn}`)
		identity = strings.TrimSpace(string(env) + " " + string(ann))
	case sopsAzureKV:
		ann, _ := w.kubectl(ctx, "-n", "argocd", "get", "serviceaccount", "argocd-repo-server",
			"-o", `jsonpath={.metadata.annotations.azure\.workload\.identity/client-id}`)
		identity = strings.TrimSpace(string(ann))
	default:
		return nil
	}
	if identity == "" {
		w.log.Warnf("argocd-repo-server has no cloud identity for %s; Argo CD will not be able to decrypt the secrets.", w.secretsMethod)
		return nil
	}
	w.log.Infof("argocd-repo-server decrypts %s secrets as: %s", w.secretsMethod, identity)
	w.log.Infof("Make sure this is %s's identity, not one copied from another environment.", w.cfg.Env)
	return nil
}
