variable "region" {
  default = "ap-south-1"
}

variable "ami_name_value" {
  default = "ami-0bb9e2d19522c61d4"
}

variable "instance_type" {
  default = "c5.2xlarge"
}

## change tag name eg. k3d-demo-your_name

variable "tag" {
    default = "k3d-demo"
}

## change ssh public_key with your public ssh key

variable "public_key" {
  default = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCrfbaDFN3FmjUoVUx4YH1eHPruFbWz6JGPfSKTwIqT75xFzU/Q6KCa3Xa6FnEOpcUKXej95pkeUnXywohojF6FrNak5p5xfGmmwC8UA9s5UxsI7flBKVnjsAbcRuxoa/AtOzg4Cizz6zQLl2JZAivZU1PwZjIJo8dcum9bjZYVHwZc3csKJ2nYgpcQrV8AWnfKtLvl5WNfNF0i5bWOieNLKiEc5DtsKYbQ6umrhhCaoGcH0S/Gy6w0PPSnnfl/AWXO7ckFtEXQbdz9Y15zeUFKgUsbklXxmC6D37BkPGu+IjCZSOttPV+PRM0Dnf0jQLvMV0UhEkguD9ALC5xikqNlFyPH5bGetWDxtLbn61tnoOIYG6lXAdk2Oe35yWWt3ZgcccWtYuRwDo0ofBwY9jWOkEcCefDyYg+S7h1VzNsbB9DsFv0vPcaxHcZK8bLdyhnz1+9rXy/flbiS5kE0O97aZ4zm4wAmqiivN2wWhUez18k2Mcs= demo@demo" 
  description = "ssh key"
}

## change ssh key_name eg. k3d-demo-your_name

variable "key_name" {
  default = "k3d-demo"  
  description = "ssh key name 
}
