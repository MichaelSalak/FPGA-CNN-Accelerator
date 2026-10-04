**1\. Mission statement**  
Our mission is to provide wildlife researchers working in remote, resource-constrained environments with an energy efficient image screening system that identifies and flags images likely to contain animals. By performing CNN inference locally on specialized FPGA hardware, the system aims to reduce unnecessary image storage, transmission, and manual review while prioritizing the preservation of potentially valuable wildlife observations.

**2\. Named user**  
The targeted user is a wildlife researcher whose research could benefit from reviewing images containing animals.

**3\. User stories**

1. As a wildlife researcher, I want the system to automatically flag images that are likely to contain an animal so that I can focus my review on images that are most likely to contain useful observations.  
2. As a wildlife researcher deploying equipment in a remote location, I want image screening to occur locally without requiring continuous network connectivity so that the monitoring system can remain useful in areas with unreliable or unavailable internet access.  
3. As a researcher concerned about missing wildlife observations, I want the classifier to prioritize detecting images that contain animals, even if some empty images are incorrectly flagged, so that potentially valuable observations are less likely to be discarded.  
4. As a researcher operating a power-constrained camera-trap system, I want image inference to consume as little energy as practical so that screening can eventually be performed on battery or solar powered equipment over long deployments.  
5. As a researcher responsible for interpreting collected data, I want the system to provide an animal/no-animal screening result rather than making a final scientific determination so that I retain responsibility for reviewing flagged images and determining their scientific significance.

**4\. Feasibility**  
	Due to difficulties in finding a general animal detection model that is both accurate and compact enough to implement on an FPGA, a more specialized dataset will be used for insect detection only ([https\://github.com/rossGardiner/ecto-trigger/](https://github.com/rossGardiner/ecto-trigger/)). This maintains the binary present/not present output while also maintaining high accuracy and a reasonable size for FPGA acceleration. Additionally, this model is pretrained and provides final weights for inference, allowing development time that would have been otherwise allocated towards training a model to instead be spent working on the accelerator. The FPGA used will be the AMD Kria KV260 Vision AI Starter Kit due to it being a Zynq board (contains both an ARM processor and an FPGA): image preprocessing can therefore be handled by the processor in software while the hardware only worries about performing inference on processed images. There is plenty of time to acquire this board before the design is ready for hardware tests, making its usage feasible within the scope of a semester. All other software environments and languages are free to access and will pose no feasibility issues.

**5\. Tooling**

* Python \- used to inspect and test the original software model  
* Verilog \- used to design an accelerator for the model  
* Vivado \- used as a development environment for the accelerator; supports synthesis, implementation, bitstream generation and verification  
* AMD Kria KV260 Vision AI Starter Kit \- FPGA board used to test the accelerator design on. Is a Zynq board, meaning it contains an ARM processor alongside the FPGA  
* Ecto-Trigger insect detection model ([https\://github.com/rossGardiner/ecto-trigger/tree/main](https://github.com/rossGardiner/ecto-trigger/tree/main)) \- pretrained model to extract weights from and accelerate inference of in hardware: used in place of a general animal detection model due to the resource and complexity constraints of larger models 

**6\. Demo Sentence**  
	At the end of two weeks, we will show the Ecto-Trigger model working in software and document the layers and tensor dimensions used within the model; from this, an accelerator block diagram will be designed that is tailored to benefit the computations performed by the model. 

**7\. Assumptions**

1. Assumption: A small, hardware-friendly CNN can accurately distinguish animal from no-animal images.  
   1. If a CNN small enough to fit on an FPGA has poor animal recall, especially under difficult lighting, camouflage, partial visibility, or distant animals, the accelerator won't provide useful screening regardless of how efficient the hardware is.  
2. Assumption: Quantization will not significantly degrade classification performance.  
   1. The project assumes the trained model can be reduced to something like INT8 while maintaining acceptable recall. If quantization substantially increases false negatives, you may need greater precision, increasing memory, arithmetic, and FPGA resource requirements.  
3. Assumption: The CNN and its intermediate data can fit within the FPGA's resource and memory constraints.  
   1. Weights, activations, intermediate feature maps, MAC units, and control logic all consume limited BRAM, DSPs, LUTs, and FFs. If the selected network exceeds the target FPGA's practical capacity, significant architectural changes would be required.  
4. Assumption: FPGA acceleration provides a meaningful energy-efficiency benefit for this workload.  
   1. The project's motivation assumes specialized FPGA inference can reduce energy consumption compared with a reasonable embedded CPU or other edge-computing solution. If static FPGA power, memory access, or other overhead dominates such a small workload, the FPGA implementation might not provide the expected advantage.  
5. Assumption: Filtering empty images actually solves an important problem for the intended user.  
   1. The proposal assumes wildlife researchers collect enough empty or irrelevant images that automatically flagging animal-containing images meaningfully reduces storage, transmission, or review effort. If researchers already have effective filtering solutions, rarely experience this problem, or cannot risk filtering images because of false negatives, the system's practical value becomes much weaker.

**8\. Evaluation with Baseline**  
	The FPGA CNN accelerator will be evaluated in terms of classification performance, hardware efficiency, and inference performance. Classification will be measured using accuracy, recall, false positive rate, and false negative rate, with particular emphasis on high recall and a low false negative rate because missed animal detections are more costly than unnecessary image flags. Hardware performance will be evaluated using inference latency, throughput, estimated power consumption, energy per inference, and FPGA resource utilization (LUTs, flip-flops, DSPs, and on-chip memory). The FPGA implementation will also be compared against a software or embedded baseline executing the same quantized CNN on the same test images. The goal is to determine whether the custom FPGA architecture can reduce inference latency and energy consumption while maintaining classification results comparable to the reference model.

**9\. Related Work**

1. R. Agrawal, L. de Castro, G. Yang, C. Juvekar, R. Yazicigil, A. Chandrakasan, V. Vaikuntanathan, and A. Joshi, “FAB: An FPGA-based Accelerator for Bootstrappable Fully Homomorphic Encryption,” arXiv:2207.11872, 2022\.   
   1. An FPGA accelerator for FHE; leaves open FPGA based CNN acceleration   
2. L. Daksha, S. Guzelhan, K. Shivdikar, C. Agulló Domingo, Ó. Vera Lopez, G. Jonatan, H. Dymarkowski, A. El Jerari, J. Cano, J. L. Abellán, J. Kim, D. Kaeli, and A. Joshi, “FHECore: Rethinking GPU Microarchitecture for Fully Homomorphic Encryption,” arXiv:2602.22229, 2026\.  
   1. A GPU core for FHE; leaves open FPGA CNN based acceleration   
3. K. Shivdikar, N. Bohm Agostini, M. Jayaweera, G. Jonatan, J. L. Abellan, A. Joshi, J. Kim, and D. Kaeli, “NeuraChip: Accelerating GNN Computations with a Hash-based Decoupled Spatial Accelerator,” arXiv:2404.15510, 2024\.  
   1. A GNN accelerator chip; leaves open FPGA CNN based acceleration 

**10\. Three Lines on Harm**  
	If the system produces a false positive, then a researcher might inspect an image that is not useful, wasting a small amount of time. If the system produces a false negative, then an image that could contain a rare or important species could be missed, potentially delaying important discoveries. The worst realistic misuse would involve manipulating the FPGA or environment to cause the system to intentionally flag more images than it should, wasting memory and researchers’ time.