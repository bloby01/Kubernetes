// Copyright 2018 The Kubernetes Authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package storage

import (
	"testing"
	"time"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	apitypes "k8s.io/apimachinery/pkg/types"
	metrics "k8s.io/metrics/pkg/apis/metrics"

	"sigs.k8s.io/metrics-server/pkg/api"
)

var defaultWindow = 30 * time.Second

func TestStorage(t *testing.T) {
	RegisterFailHandler(Fail)
	RunSpecs(t, "Storage Suite")
}

func newMilliPoint(ts time.Time, cpu, memory int64) MetricsPoint {
	return MetricsPoint{
		Timestamp:   ts,
		CpuUsage:    *resource.NewMilliQuantity(cpu, resource.DecimalSI),
		MemoryUsage: *resource.NewMilliQuantity(memory, resource.BinarySI),
	}
}

var _ = Describe("In-memory Storage", func() {
	var (
		batch   *MetricsBatch
		storage *Storage
		now     time.Time
	)

	BeforeEach(func() {
		now = time.Now()
		batch = &MetricsBatch{
			Nodes: []NodeMetricsPoint{
				{Name: "node1", MetricsPoint: newMilliPoint(now.Add(100*time.Millisecond), 110, 120)},
				{Name: "node2", MetricsPoint: newMilliPoint(now.Add(200*time.Millisecond), 210, 220)},
				{Name: "node3", MetricsPoint: newMilliPoint(now.Add(300*time.Millisecond), 310, 320)},
			},
			Pods: []PodMetricsPoint{
				{Name: "pod1", Namespace: "ns1", Containers: []ContainerMetricsPoint{
					{Name: "container1", MetricsPoint: newMilliPoint(now.Add(400*time.Millisecond), 410, 420)},
					{Name: "container2", MetricsPoint: newMilliPoint(now.Add(500*time.Millisecond), 510, 520)},
				}},
				{Name: "pod2", Namespace: "ns1", Containers: []ContainerMetricsPoint{
					{Name: "container1", MetricsPoint: newMilliPoint(now.Add(600*time.Millisecond), 610, 620)},
				}},
				{Name: "pod1", Namespace: "ns2", Containers: []ContainerMetricsPoint{
					{Name: "container1", MetricsPoint: newMilliPoint(now.Add(700*time.Millisecond), 710, 720)},
					{Name: "container2", MetricsPoint: newMilliPoint(now.Add(800*time.Millisecond), 810, 820)},
				}},
			},
		}

		storage = NewStorage()
	})

	It("should receive batches of metrics", func() {
		By("storing the batch")
		Expect(storage.Store(batch)).To(Succeed())

		By("making sure that the storage contains all nodes received")
		for _, node := range batch.Nodes {
			_, _, err := storage.GetNodeMetrics(node.Name)
			Expect(err).NotTo(HaveOccurred())
		}

		By("making sure that the storage contains all pods received")
		for _, pod := range batch.Pods {
			_, _, err := storage.GetContainerMetrics(apitypes.NamespacedName{
				Name:      pod.Name,
				Namespace: pod.Namespace,
			})
			Expect(err).NotTo(HaveOccurred())
		}
	})

	It("should not error out if duplicate nodes were received, with a partial store", func() {
		By("adding a duplicate node to the batch")
		batch.Nodes = append(batch.Nodes, batch.Nodes[0])

		By("storing the batch and checking for an error")
		Expect(storage.Store(batch)).To(Succeed())

		By("making sure none of the data is in the storage")
		for _, node := range batch.Nodes {
			_, res, err := storage.GetNodeMetrics(node.Name)
			Expect(err).NotTo(HaveOccurred())
			Expect(res).To(ConsistOf(corev1.ResourceList{
				corev1.ResourceName(corev1.ResourceCPU):    node.CpuUsage,
				corev1.ResourceName(corev1.ResourceMemory): node.MemoryUsage,
			}))
		}
		for _, pod := range batch.Pods {
			_, res, err := storage.GetContainerMetrics(apitypes.NamespacedName{
				Name:      pod.Name,
				Namespace: pod.Namespace,
			})
			Expect(err).NotTo(HaveOccurred())
			Expect(res).NotTo(Equal([][]metrics.ContainerMetrics{nil}))
		}
	})

	It("should not error out if duplicate pods were received, with a partial store", func() {
		By("adding a duplicate pod to the batch")
		batch.Pods = append(batch.Pods, batch.Pods[0])

		By("storing and checking for an error")
		Expect(storage.Store(batch)).To(Succeed())

		By("making sure none of the data is in the storage")
		for _, node := range batch.Nodes {
			_, res, err := storage.GetNodeMetrics(node.Name)
			Expect(err).NotTo(HaveOccurred())
			Expect(res).To(ConsistOf(corev1.ResourceList{
				corev1.ResourceName(corev1.ResourceCPU):    node.CpuUsage,
				corev1.ResourceName(corev1.ResourceMemory): node.MemoryUsage,
			}))
		}
		for _, pod := range batch.Pods {
			_, res, err := storage.GetContainerMetrics(apitypes.NamespacedName{
				Name:      pod.Name,
				Namespace: pod.Namespace,
			})
			Expect(err).NotTo(HaveOccurred())
			Expect(res).NotTo(Equal([][]metrics.ContainerMetrics{nil}))
		}
	})

	It("should retrieve metrics for all containers in a pod, with overall latest scrape time", func() {
		By("storing and checking for an error")
		Expect(storage.Store(batch)).To(Succeed())

		By("fetching the pod")
		ts, containerMetrics, err := storage.GetContainerMetrics(apitypes.NamespacedName{
			Name:      "pod1",
			Namespace: "ns1",
		})
		Expect(err).NotTo(HaveOccurred())

		By("verifying that the timestamp is the smallest time amongst all containers")
		Expect(ts).To(ConsistOf(api.TimeInfo{Timestamp: now.Add(400 * time.Millisecond), Window: defaultWindow}))

		By("verifying that all containers have data")
		Expect(containerMetrics).To(Equal(
			[][]metrics.ContainerMetrics{
				{
					{
						Name: "container1",
						Usage: corev1.ResourceList{
							corev1.ResourceCPU:    *resource.NewMilliQuantity(410, resource.DecimalSI),
							corev1.ResourceMemory: *resource.NewMilliQuantity(420, resource.BinarySI),
						},
					},
					{
						Name: "container2",
						Usage: corev1.ResourceList{
							corev1.ResourceCPU:    *resource.NewMilliQuantity(510, resource.DecimalSI),
							corev1.ResourceMemory: *resource.NewMilliQuantity(520, resource.BinarySI),
						},
					},
				},
			},
		))
	})

	It("should return nil metrics for missing pods", func() {
		By("storing and checking for an error")
		Expect(storage.Store(batch)).To(Succeed())

		By("fetching the a present pod and a missing pod")
		ts, containerMetrics, err := storage.GetContainerMetrics(apitypes.NamespacedName{
			Name:      "pod1",
			Namespace: "ns1",
		}, apitypes.NamespacedName{
			Name:      "pod2",
			Namespace: "ns42",
		})
		Expect(err).NotTo(HaveOccurred())

		By("verifying that the timestamp is the smallest time amongst all containers")
		Expect(ts).To(Equal([]api.TimeInfo{{Timestamp: now.Add(400 * time.Millisecond), Window: defaultWindow}, {}}))

		By("verifying that all present containers have data")
		Expect(containerMetrics).To(Equal(
			[][]metrics.ContainerMetrics{
				{
					{
						Name: "container1",
						Usage: corev1.ResourceList{
							corev1.ResourceCPU:    *resource.NewMilliQuantity(410, resource.DecimalSI),
							corev1.ResourceMemory: *resource.NewMilliQuantity(420, resource.BinarySI),
						},
					},
					{
						Name: "container2",
						Usage: corev1.ResourceList{
							corev1.ResourceCPU:    *resource.NewMilliQuantity(510, resource.DecimalSI),
							corev1.ResourceMemory: *resource.NewMilliQuantity(520, resource.BinarySI),
						},
					},
				},
				nil,
			},
		))

	})

	It("should retrieve metrics for a node, with overall latest scrape time", func() {
		By("storing and checking for an error")
		Expect(storage.Store(batch)).To(Succeed())

		By("fetching the nodes")
		ts, nodeMetrics, err := storage.GetNodeMetrics("node1", "node2")
		Expect(err).NotTo(HaveOccurred())

		By("verifying that the timestamp is the smallest time amongst all containers")
		Expect(ts).To(Equal([]api.TimeInfo{{Timestamp: now.Add(100 * time.Millisecond), Window: defaultWindow}, {Timestamp: now.Add(200 * time.Millisecond), Window: defaultWindow}}))

		By("verifying that all nodes have data")
		Expect(nodeMetrics).To(Equal(
			[]corev1.ResourceList{
				{
					corev1.ResourceCPU:    *resource.NewMilliQuantity(110, resource.DecimalSI),
					corev1.ResourceMemory: *resource.NewMilliQuantity(120, resource.BinarySI),
				},
				{
					corev1.ResourceCPU:    *resource.NewMilliQuantity(210, resource.DecimalSI),
					corev1.ResourceMemory: *resource.NewMilliQuantity(220, resource.BinarySI),
				},
			},
		))
	})

	It("should return nil metrics for missing nodes", func() {
		By("storing and checking for an error")
		Expect(storage.Store(batch)).To(Succeed())

		By("fetching the nodes, plus a missing node")
		ts, nodeMetrics, err := storage.GetNodeMetrics("node1", "node2", "node42")
		Expect(err).NotTo(HaveOccurred())

		By("verifying that the timestamp is the smallest time amongst all containers")
		Expect(ts).To(Equal([]api.TimeInfo{{Timestamp: now.Add(100 * time.Millisecond), Window: defaultWindow}, {Timestamp: now.Add(200 * time.Millisecond), Window: defaultWindow}, {}}))

		By("verifying that all present nodes have data")
		Expect(nodeMetrics).To(Equal(
			[]corev1.ResourceList{
				{
					corev1.ResourceCPU:    *resource.NewMilliQuantity(110, resource.DecimalSI),
					corev1.ResourceMemory: *resource.NewMilliQuantity(120, resource.BinarySI),
				},
				{
					corev1.ResourceCPU:    *resource.NewMilliQuantity(210, resource.DecimalSI),
					corev1.ResourceMemory: *resource.NewMilliQuantity(220, resource.BinarySI),
				},
				nil,
			},
		))

	})
})
