---
hide:
  #- navigation
  - toc
---
# Installing OpenShift in a Disconnected/Air-Gapped Environment: Streamlined
This documents purpose is for consolidating information to install an OpenShift v4.14 and later cluster in a disconnected/air-gap environment using the agent-based installer on bare metal/virtual infrastructure. 

This is not one-size fits all, or specific to any team/org, just rough and fairly simple to at least put the important information in one centralized document. 

Most of this was written for OpenShift v4.17, but you can follow this process for any version later than v4.14, just sub in whatever version of the platform you want.

- Relevant docs/articles are linked in each section if applicable. 
- CLI commands are included within the documentation along with associated output. 

---

![disco-diagram](./assets/images/disco-diagram.png)