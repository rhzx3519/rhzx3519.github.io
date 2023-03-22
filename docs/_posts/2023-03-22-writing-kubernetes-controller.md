---
layout: post
title:  "Writing a Kubernetes Controller"
date:   2023-03-22 0:30:27 +1100
categories: DevOps
tags: Kubernetes Controller Cloud-Native
---

![Kubernetes controller](/assets/images/kubernetes-controller/controller.png)

All code of this article is available in [here](https://github.com/Devops-in-Wollongong/writing-kubernetes-controller).

# Introduction

This is an article based on the [Writing Kubernetes Controllers](https://www.youtube.com/watch?v=q7b23612pSc) 
released by @Peter Jausovec. In this article, I record the necessary commands and steps to implement a 
basic Kubernetes controller through [KuberBuilder](https://book.kubebuilder.io/).

# Prerequisites

- [Kind](https://kind.sigs.k8s.io/) - kind is a tool for running local Kubernetes clusters using Docker container “nodes”.
- [KuberBuilder](https://book.kubebuilder.io/) - Kubebuilder is a framework for building Kubernetes APIs using custom resource definitions (CRDs).

# Objectives

![pdfdocument-diagram.png](/assets/images/kubernetes-controller/pdfdocument-diagram.png)

PdfDocument is a CRD that we defined inside Kubernetes, and a pdfdocument controller is created to
handle pdfdocument. The controller create a job to save the text we defined in pdfdocument to .md file, and then 
convert .md file to .pdf file in the volume. Eventually, we could obtain a pdf file stored in the shared volume 
through Kubernetes rest apis.

# Define CRD Manually

First, we must create the CustomResourceDefinition, so that Kubernetes can recognize the new resource.
The definition is represented as a yaml file.

```yaml
# pdf-crd.yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: pdfdocuments.k8s.startkubernetes.com
spec:
  group: k8s.startkubernetes.com
  names:
    kind: PdfDocument
    singular: pdfdocument
    plural: pdfdocuments
    shortNames: 
      - pdf
      - pdfs
  scope: Namespaced
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                documentName:
                  type: string
                text:
                  type: string
```


Then we declare a pdfdocument through a yaml file.

```yaml
# pdfdocument.yaml
apiVersion: k8s.startkubernetes.com/v1
kind: PdfDocument
metadata:
  name: my-document
spec:
  documentName: my-text
  text: |-
    ### My document
    Hello **world!**!
```

We use kubectl to create crd in Kubernetes.

```shell
❯ kubectl apply -f pdf-crd.yaml
customresourcedefinition.apiextensions.k8s.io/pdfdocuments.k8s.startkubernetes.com created

❯ kubectl apply -f pdfdocument.yaml
pdfdocument.k8s.startkubernetes.com/my-document created                                                                    ─╯

❯ kl get pdf
NAME          AGE                                                                                                          ─╯
my-document   3s
```

we can also visit my-document through rest APIs in kubernetes.
```shell
❯ kubectl proxy --port 8080
Starting to serve on 127.0.0.1:8080

❯ curl localhost:8080/apis/k8s.startkubernetes.com/v1/namespaces/writing-controller/pdfdocuments
{
  "apiVersion": "k8s.startkubernetes.com/v1",
  ...
}
```

You can see from the shell, a pdfdocument is created. But for now, it is meaningless,
there is no logic in Kubernetes can handle this pdfdocument kind resource.
We need to build a controller to manage the crd resource.

# Write a Kubernetes controller

Using KubeBuilder is more efficient to create a new crd.

```shell
❯ mkdir pdfcontroller && cd pdfcontroller
❯ go mod init k8s.startkubernetes.com/v1
❯ kubebuilder init --domain ''
❯ go mod tidy
❯ make
❯ kubebuilder create api --group k8s.startkubernetes.com --version v1 --kind PdfDocument
Create Resource[y/n]
y
...
❯ make
```

The crd is defined in .go file and represented as struct. For pdfdocument, we can find its .go file at
`/api/v1/pdfdocument_types.go`. We add two fields, DocumentName and Text, in PdfDocumentSpec, and
we add `//+kubebuilder:resource:shortName=pdf;pdfs` comments on PdfDocument to define shortnames.

```go
type PdfDocumentSpec struct {
  // INSERT ADDITIONAL SPEC FIELDS - desired state of cluster
  // Important: Run "make" to regenerate code after modifying this file
	
	// Foo is an example field of PdfDocument. Edit pdfdocument_types.go to remove/update
  DocumentName string `json:"documentName,omitEmpty"`
  Text         string `json:"text,omitempty"`
}


//+kubebuilder:object:root=true
//+kubebuilder:resource:shortName=pdf;pdfs
//+kubebuilder:subresource:status

// PdfDocument is the Schema for the pdfdocuments API
type PdfDocument struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   PdfDocumentSpec   `json:"spec,omitempty"`
	Status PdfDocumentStatus `json:"status,omitempty"`
}
```

Then we run `make` command to regenerate configuration.
We can find crd definition yaml file in the below path.

```shell
❯ tree config/crd/bases
config/crd/bases
└── k8s.startkubernetes.com_pdfdocuments.yaml
❯ kubectl apply -f config/crd/bases/k8s.startkubernetes.com_pdfdocuments.yaml
customresourcedefinition.apiextensions.k8s.io/pdfdocuments.k8s.startkubernetes.com created     
```

The real logic is in `controllers/pdfdocument_controller.go::Reconcile` [function](https://github.com/Devops-in-Wollongong/writing-kubernetes-controller/blob/master/pdfcontroller/controllers/pdfdocument_controller.go#L54).

We can run `make run` to make controller run on our local machine.
Then we create a new pdfdocument.

```shell
❯ kubectl apply -f pdfdocument.yaml                                                                                                                                                     ─╯
pdfdocument.k8s.startkubernetes.com/my-document created
 ~/Documents/Code/mysources/writing-kubernetes-controller ·························································································· kind-kind-1/writing-controller ⎈ ─╮
❯ kl get pdf                                                                                                                                                                            ─╯
NAME          AGE
my-document   3s
 ~/Documents/Code/mysources/writing-kubernetes-controller ·························································································· kind-kind-1/writing-controller ⎈ ─╮
❯ kl get jobs                                                                                                                                                                           ─╯
NAME              COMPLETIONS   DURATION   AGE
my-document-job   0/1           5s         5s
 ~/Documents/Code/mysources/writing-kubernetes-controller ·························································································· kind-kind-1/writing-controller ⎈ ─╮
❯ kl get pods                                                                                                                                                                           ─╯
NAME                    READY   STATUS     RESTARTS   AGE
my-document-job-vq9zh   0/1     Init:1/2   0          8s
 ~/Documents/Code/mysources/writing-kubernetes-controller ·························································································· kind-kind-1/writing-controller ⎈ ─╮
❯ kl get pods -w                                                                                                                                                                        ─╯
NAME                    READY   STATUS     RESTARTS   AGE
my-document-job-vq9zh   0/1     Init:1/2   0          11s
my-document-job-vq9zh   0/1     PodInitializing   0          22s
my-document-job-vq9zh   1/1     Running           0          25s
```

A job and a subsequent pod is created.

Use `kubectl cp` command to copy file from Kubernetes.

```shell
kubectl cp my-document-job-vq9zh:/data/my-text.pdf ${PWD}/my-text.pdf
```

Finally, we can obtain a pdf file named my-text.pdf, and the content is just as
same as we defined in the PdfDocument yaml.













