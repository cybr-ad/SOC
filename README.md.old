# SOC

Yes — here is the complete, ready-to-upload README.md. It is already formatted as GitHub Markdown with headings, diagrams, tables, and sections.

Just save the content below as README.md and upload it to GitHub.
SOC Analyst Lab — README.md
🛡️ SOC Analyst Lab

    A practical SOC lab for centralized security monitoring, log collection, detection, and investigation using Windows Server, Ubuntu Linux, Sysmon, and Splunk Enterprise.

📌 Overview

This project demonstrates a small enterprise-style SOC environment built with VMware.

The lab contains:

    🏢 Windows Server / Domain Controller

    🐧 Ubuntu Linux Server

    🖥️ Windows Host running Splunk Enterprise

    🔬 Sysmon

    📡 Splunk Universal Forwarder

    🌐 VMware VMnet8 network

The main goal is to collect security telemetry from Windows and Linux systems and analyze it centrally in Splunk.
🗺️ Lab Architecture

                         VMware VMnet8
                      192.168.10.0/24
                              │
              ┌───────────────┼───────────────┐
              │               │               │
              ▼               ▼               ▼
       ┌────────────┐   ┌────────────┐   ┌────────────┐
       │ DC01-CORP  │   │   Ubuntu   │   │  Windows   │
       │            │   │            │   │    Host    │
       │192.168.10.20│  │192.168.10.30│  │192.168.10.1│
       │            │   │            │   │            │
       │ AD + DNS   │   │ SSH+auditd │   │   Splunk   │
       └─────┬──────┘   └──────┬─────┘   └──────┬─────┘
             │                 │                │
             │                 │                │
             └──── DNS / Network ───────────────┘
                                               │
                                               ▼
                                          TCP :9997

🌐 Network Configuration
System	Role	IP Address
DC01-CORP	Active Directory + DNS	192.168.10.20
srv-linux-01	Ubuntu Linux Server	192.168.10.30
Windows Host	Splunk Enterprise	192.168.10.1
VMware VMnet8	Lab Network	192.168.10.0/24
VMware Gateway	NAT Gateway	192.168.10.2
🔗 Windows Server ↔ Ubuntu

Windows Server and Ubuntu are connected to the same VMware VMnet8 network.

┌─────────────────────┐
│     DC01-CORP       │
│    192.168.10.20    │
│                     │
│   Active Directory  │
│        + DNS        │
└──────────┬──────────┘
           │
           │ Network
           │
           ▼
┌─────────────────────┐
│    srv-linux-01     │
│    192.168.10.30    │
│                     │
│    Ubuntu Linux     │
│      SSH + auditd   │
└─────────────────────┘

Ubuntu network configuration:

IP:       192.168.10.30
Gateway:  192.168.10.2
DNS:      192.168.10.20
          1.1.1.1

Ubuntu uses DC01-CORP (192.168.10.20) as its primary DNS server.
📡 Log Forwarding Architecture

Windows Server and Ubuntu do not forward logs through each other.

Each system independently sends its telemetry to the Splunk server.

                    ┌──────────────────────┐
                    │   Windows Server     │
                    │    192.168.10.20     │
                    └──────────┬───────────┘
                               │
                               │ Universal
                               │ Forwarder
                               ▼
                         ┌─────────────┐
                         │             │
                         │   Splunk    │
                         │ 192.168.10.1 │
                         │    :9997    │
                         │             │
                         └─────────────┘
                               ▲
                               │
                               │ Universal
                               │ Forwarder
                               │
                    ┌──────────┴───────────┐
                    │      Ubuntu         │
                    │    192.168.10.30    │
                    └──────────────────────┘

Log Flow

Windows Server
      │
      └──── Universal Forwarder ────►
                                     │
                                     ▼
                              Splunk :9997
                                     ▲
                                     │
      ┌──── Universal Forwarder ────┘
      │
Ubuntu Linux

🧩 System Roles
🏢 Windows Server — DC01-CORP

Role:
├── Active Directory
├── DNS
├── Windows Security Events
├── System Events
├── PowerShell Events
└── Sysmon Telemetry

Windows Server provides:

    Active Directory services

    DNS for the lab domain

    Windows security telemetry

    PowerShell logging

    Sysmon telemetry

🐧 Ubuntu — srv-linux-01

Role:
├── Linux Server
├── SSH
├── auditd
└── Linux Security Logs

Important log sources:

/var/log/auth.log
/var/log/audit/audit.log
/var/log/linux_attacks_sample.log

Ubuntu uses:

Primary DNS → 192.168.10.20
Gateway     → 192.168.10.2

🖥️ Windows Host — Splunk

The Windows host runs Splunk Enterprise and acts as the centralized SIEM/log receiver.

Splunk Server
IP:   192.168.10.1
Port: 9997

🔬 Windows Telemetry

The Windows environment collects:

┌─────────────────────────┐
│     Windows Telemetry   │
├─────────────────────────┤
│ Security Events         │
│ System Events           │
│ Application Events      │
│ PowerShell Events       │
│ Sysmon Events           │
└─────────────────────────┘
              │
              ▼
      Splunk Universal
         Forwarder
              │
              ▼
       Splunk :9997

🐧 Linux Telemetry

Linux telemetry is collected from:

┌──────────────────────────────┐
│       Linux Telemetry        │
├──────────────────────────────┤
│ /var/log/auth.log            │
│ /var/log/audit/audit.log     │
│ linux_attacks_sample.log     │
└──────────────────────────────┘
                │
                ▼
        Splunk Forwarder
                │
                ▼
         Splunk :9997

📊 Splunk Indexes

The lab uses separate indexes for different telemetry sources.
Index	Data
win_logs	Windows event logs
sysmon	Sysmon telemetry
linux_logs	Linux security logs
🔎 SOC Investigation Workflow

The lab follows a simple SOC workflow:

       📥 LOG COLLECTION
              │
              ▼
        🔎 DETECTION
              │
              ▼
          🚨 ALERT
              │
              ▼
        🧑‍💻 TRIAGE
              │
              ▼
       🔬 INVESTIGATION
              │
              ▼
        🔗 CORRELATION
              │
              ▼
        📝 DOCUMENTATION

🧪 Sample Security Events

The Windows lab includes controlled sample security data:

C:\Logs\windows_attacks_sample.log

This can be used to practice:

    Event investigation

    Detection development

    Splunk searches

    Alert analysis

    SOC reporting

📁 Project Structure

SOC-Analyst-Lab/
│
├── README.md
│
├── windows/
│   └── win-server.ps1
│
├── linux/
│   └── linux.sh
│
├── splunk/
│   ├── indexes/
│   ├── inputs/
│   └── searches/
│
├── screenshots/
│   ├── architecture.png
│   ├── splunk-dashboard.png
│   ├── windows-events.png
│   ├── sysmon-events.png
│   └── linux-events.png
│
└── docs/
    └── SOC-Lab-Manual.pdf

⚙️ Configuration Summary

┌─────────────────────────────────────────┐
│              SOC LAB                    │
├─────────────────────────────────────────┤
│ Network       192.168.10.0/24           │
│ Gateway       192.168.10.2              │
│                                         │
│ DC01-CORP     192.168.10.20             │
│ Ubuntu        192.168.10.30             │
│ Splunk Host   192.168.10.1              │
│                                         │
│ Splunk Port   TCP 9997                  │
│ Domain        corp.local                │
└─────────────────────────────────────────┘

🛠️ Technologies
Technology	Purpose
🛡️ Splunk Enterprise	SIEM & Log Analysis
🪟 Windows Server	AD & DNS
🐧 Ubuntu	Linux Server
🔬 Sysmon	Windows Telemetry
📡 Universal Forwarder	Log Collection
⚡ PowerShell	Windows Automation
🔐 auditd	Linux Auditing
🌐 VMware VMnet8	Network Isolation
🎯 Learning Objectives

This lab provides practical experience with:

✓ SOC Monitoring
✓ SIEM Operations
✓ Windows Event Analysis
✓ Linux Log Analysis
✓ Sysmon Investigation
✓ PowerShell Monitoring
✓ Authentication Monitoring
✓ Security Alert Triage
✓ Threat Detection
✓ Incident Investigation
✓ Security Automation

📸 Screenshots

Add screenshots from the lab here:
🛡️ Splunk Dashboard


🪟 Windows Events


🔬 Sysmon Events


🐧 Linux Events


🚀 Lab Flow

        ┌───────────────┐
        │ VMware VMnet8  │
        └───────┬───────┘
                │
       ┌────────┴─────────┐
       │                  │
       ▼                  ▼
 Windows Server         Ubuntu
 DC01-CORP           srv-linux-01
       │                  │
       │                  │
       └────────┬─────────┘
                │
                │ Telemetry
                ▼
       ┌─────────────────┐
       │     Splunk      │
       │ 192.168.10.1    │
       │     :9997       │
       └────────┬────────┘
                │
                ▼
       🔎 SOC Investigation

🏁 Result

The completed lab provides a centralized SOC monitoring environment where:

Windows + Linux → Telemetry → Splunk → Detection → Investigation

The architecture keeps network communication, DNS, and log forwarding logically separated, making it easier to understand how an enterprise SOC collects and analyzes security telemetry.
👨‍💻 SOC Analyst Lab

Built for hands-on cybersecurity learning, SOC monitoring, SIEM analysis, and blue-team practice.

This version is ready to paste directly into GitHub as README.md; GitHub will render the diagrams, tables, headings, and screenshots automatically.

download of readme.md file

Data analysis isn't available right now. Do you want to continue without it?

ALways remember Yes. The previous prompt still leaves room for an AI to render Markdown in the conversation. You need to make the file itself the only deliverable, with a hard failure rule if file creation isn't possible.

Use this stronger version:

# SYSTEM: README FILE-ONLY GENERATOR

You are operating in STRICT FILE-OUTPUT MODE.

Your task is to create a GitHub-ready README file from the information I provide.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ABSOLUTE OUTPUT RULE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CREATE EXACTLY ONE FILE:

README.md

The README content MUST exist inside the file itself.

The chat/message response MUST NOT contain the README content.

The chat/message response MUST NOT contain a Markdown rendering of the README.

The chat/message response MUST NOT contain a preview of the README.

The chat/message response MUST NOT contain a code block containing the README.

The chat/message response MUST NOT contain an explanation.

The chat/message response MUST NOT contain a summary.

The chat/message response MUST NOT contain headings.

The chat/message response MUST NOT contain "Here is your README".

The chat/message response MUST NOT contain "Done".

The chat/message response MUST NOT contain any additional text.

The ONLY deliverable is the actual downloadable file:

README.md


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RAW FILE CONTENT REQUIREMENT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Inside README.md, write the actual RAW Markdown source.

The file must contain real Markdown characters and syntax, including when required:

#
##
###
**
*
-
1.
>
|
[link](url)
![image](url)
<details>
<summary>


Do NOT escape Markdown simply to prevent rendering.

Do NOT replace Markdown syntax with descriptions.

For example, the file must contain:

## Installation

and NOT:

\## Installation

The file must contain actual fenced code blocks such as:

```bash
npm install

The triple backticks above are characters that must physically exist inside README.md.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
CRITICAL: DO NOT WRAP THE FILE CONTENT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

NEVER place the complete README inside another outer code block.

NEVER return:

# Project
...

The README itself is the file.

The outer chat response must contain NO README content whatsoever.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FILE CREATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

If your environment supports file creation, file attachments, artifacts, sandbox files, code execution, or document generation:

USE THAT CAPABILITY.

Create:

README.md

Write the complete README source into that file.

Then attach/return that file.

Do NOT copy the contents of the file into the chat response.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FAILURE CONDITION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

If you cannot actually create and attach a file in this environment:

DO NOT paste the README into the chat.

DO NOT attempt to simulate a file using a Markdown code block.

DO NOT render the README.

DO NOT provide the README as normal text.

Return ONLY:

FILE CREATION NOT SUPPORTED

Nothing else.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
README QUALITY REQUIREMENTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

The generated README.md must be:

    GitHub-compatible
    valid Markdown
    professional
    readable when rendered by GitHub
    complete
    technically accurate
    logically organized
    consistent in formatting
    directly uploadable to a GitHub repository

Use appropriate sections when applicable, such as:
Project Name
Overview
Features
Architecture
Requirements
Installation
Configuration
Environment Variables
Usage
Commands
API
Project Structure
Examples
Development
Testing
Deployment
Troubleshooting
FAQ
Contributing
License

Do NOT add irrelevant sections just to make the README longer.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SOURCE-OF-TRUTH RULE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Use the information I provide as the primary source of truth.

If I provide:

    existing README content
    project documentation
    source code
    configuration
    directory structure
    commands
    environment variables
    API information
    screenshots
    repository information
    technical requirements

use those materials when constructing the README.

Do NOT invent technical facts.

Do NOT invent:

    package names
    commands
    URLs
    APIs
    dependencies
    configuration values
    environment variables
    repository links
    badges
    versions
    features
    authors
    licenses

If something genuinely required is unknown, use a clearly identifiable placeholder such as:

YOUR_VALUE_HERE

Do not fabricate information.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
MARKDOWN INTEGRITY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Before creating the file, internally validate the complete README.

Check:

    Markdown headings.
    Heading hierarchy.
    Lists.
    Numbered lists.
    Tables.
    Links.
    Images.
    HTML elements.
    <details> / <summary> blocks.
    Code fences.
    Nested code examples.
    Shell commands.
    JSON examples.
    YAML examples.
    Environment-variable examples.
    File trees.
    Special characters.
    Badge syntax.
    Internal anchors.
    Overall GitHub rendering.

Every opened code fence must have a matching closing fence.

Every table must have valid separators.

Every HTML element intentionally used must be properly structured.

Do not accidentally terminate a code block early.

Do not accidentally turn README source into chat formatting.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
CODE BLOCK RULE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Code blocks belong INSIDE README.md.

They must be written as actual Markdown:

command

{
  "example": true
}

example: value

Do not remove the triple backticks.

Do not convert them into indentation unless specifically required.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
VISUAL QUALITY RULE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

The README should look polished AFTER GitHub renders it.

However:

THE RAW FILE MUST REMAIN RAW MARKDOWN.

Do not optimize the chat appearance.

Optimize the actual README.md file for GitHub rendering.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
NO CHAT PREVIEW RULE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

The README is NOT a response.

The README is an ARTIFACT/FILE.

Therefore:

CHAT = NO README CONTENT

FILE = COMPLETE README CONTENT

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FINAL EXECUTION PROTOCOL
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Follow this exact sequence internally:

    Analyze my provided information.
    Determine the README structure.
    Write the complete raw Markdown.
    Validate the Markdown.
    Create a physical file named README.md.
    Put the raw Markdown into that file.
    Verify the file contents.
    Return ONLY the file attachment.
    Do not print the file contents into the conversation.

The final response must contain NO explanatory text.

The final response must contain NO Markdown README preview.

The final response must contain NO code block.

The final response must contain NO duplicate copy of the file.

ONLY:

[README.md FILE ATTACHMENT]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
USER INPUT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Everything below this line is source material/instructions for the README.

[PASTE YOUR PROJECT INFORMATION HERE]


### The most important part

The **failure condition** makes this much stronger:

> If you cannot actually create and attach a file, **DO NOT paste the README**. Return only `FILE CREATION NOT SUPPORTED`.

That prevents the AI from falling back to the exact behavior shown in your screenshot.

Also, don't ask the AI to "make a text file" while naming it `README.md`. Explicitly tell it that **`README.md` itself is the one and only file**, and that the raw Markdown exists **inside the attachment**, not in the chat.


Memory updated

now provide my desired  README.md

README.md
README.mdDocument
LOCKDOWN MODE


🛡️ SOC Analyst Lab

A simple hands-on SOC lab built with VMware, Windows Server, Ubuntu Linux, Sysmon, Splunk Enterprise, and Splunk Universal Forwarder.

The lab is designed to practice log collection, security monitoring, detection, triage, investigation, and SIEM analysis in a small isolated environment.
🗺️ Lab Architecture

                         VMware VMnet8
                      192.168.10.0/24
                              │
              ┌───────────────┼───────────────┐
              │               │               │
              ▼               ▼               ▼
       ┌────────────┐   ┌────────────┐   ┌────────────┐
       │ DC01-CORP  │   │srv-linux-01│   │Windows Host│
       │192.168.10.20│  │192.168.10.30│  │192.168.10.1│
       │            │   │            │   │            │
       │ AD + DNS   │   │ SSH+auditd │   │   Splunk   │
       └─────┬──────┘   └─────┬──────┘   └─────┬──────┘
             │                │                │
             │                │                │
             └──── DNS / Network ─────────────┘
                                              │
                                              ▼
                                         TCP :9997

🌐 Network Configuration
System	Role	IP Address
DC01-CORP	Active Directory + DNS	192.168.10.20
srv-linux-01	Ubuntu Linux Server	192.168.10.30
Windows Host	Splunk Enterprise	192.168.10.1
VMware VMnet8	Lab Network	192.168.10.0/24
VMware Gateway	NAT Gateway	192.168.10.2
🔗 Windows Server ↔ Ubuntu

Windows Server and Ubuntu are connected to the same VMware VMnet8 network, so they can communicate directly.

┌─────────────────────┐
│     DC01-CORP       │
│    192.168.10.20    │
│                     │
│   Active Directory  │
│        + DNS        │
└──────────┬──────────┘
           │
           │ Same VMnet8 Network
           │
           ▼
┌─────────────────────┐
│    srv-linux-01     │
│    192.168.10.30    │
│                     │
│    Ubuntu Linux     │
│      SSH + auditd   │
└─────────────────────┘

Ubuntu Network Configuration

IP:       192.168.10.30
Gateway:  192.168.10.2
DNS:      192.168.10.20
          1.1.1.1

Ubuntu uses DC01-CORP (192.168.10.20) as its primary DNS server.
📡 Log Forwarding Architecture

Windows Server and Ubuntu do not forward logs through each other.

Each system independently sends telemetry to the Splunk server on the Windows host.

┌─────────────────────┐
│   Windows Server    │
│    192.168.10.20    │
└──────────┬──────────┘
           │
           │ Universal Forwarder
           │
           ▼
     ┌─────────────────┐
     │     Splunk      │
     │  192.168.10.1   │
     │    TCP :9997    │
     └─────────────────┘
           ▲
           │
           │ Universal Forwarder
           │
┌──────────┴──────────┐
│      Ubuntu         │
│    192.168.10.30    │
└─────────────────────┘

Simple Log Flow

Windows Server ────────► Splunk :9997

Ubuntu Linux ──────────► Splunk :9997

🧩 System Roles
🏢 Windows Server — DC01-CORP

Role:
├── Active Directory
├── DNS
├── Windows Security Events
├── System Events
├── PowerShell Events
└── Sysmon Telemetry

Windows Server provides the lab's Active Directory and primary DNS services and generates Windows security telemetry for Splunk.
🐧 Ubuntu — srv-linux-01

Role:
├── Linux Server
├── SSH
├── auditd
└── Linux Security Logs

Important Linux log sources:

/var/log/auth.log
/var/log/audit/audit.log
/var/log/linux_attacks_sample.log

🖥️ Windows Host — Splunk

The Windows host runs Splunk Enterprise and receives telemetry from the lab systems.

IP:   192.168.10.1
Port: 9997

🔬 Windows Telemetry

┌─────────────────────────┐
│     Windows Telemetry   │
├─────────────────────────┤
│ Security Events         │
│ System Events           │
│ Application Events      │
│ PowerShell Events       │
│ Sysmon Events           │
└─────────────────────────┘
              │
              ▼
      Splunk Universal
         Forwarder
              │
              ▼
       Splunk :9997

🐧 Linux Telemetry

┌──────────────────────────────┐
│       Linux Telemetry        │
├──────────────────────────────┤
│ /var/log/auth.log            │
│ /var/log/audit/audit.log     │
│ /var/log/linux_attacks_sample.log │
└──────────────────────────────┘
                │
                ▼
        Splunk Forwarder
                │
                ▼
         Splunk :9997

📊 Splunk Indexes
Index	Data
win_logs	Windows event logs
sysmon	Sysmon telemetry
linux_logs	Linux security logs
🔎 SOC Investigation Workflow

       📥 LOG COLLECTION
              │
              ▼
        🔎 DETECTION
              │
              ▼
          🚨 ALERT
              │
              ▼
        🧑‍💻 TRIAGE
              │
              ▼
       🔬 INVESTIGATION
              │
              ▼
        🔗 CORRELATION
              │
              ▼
        📝 DOCUMENTATION

🧪 Sample Security Events

The Windows lab includes controlled sample security data:

C:\Logs\windows_attacks_sample.log

This can be used for:

    Splunk searches

    Event investigation

    Detection testing

    Alert analysis

    SOC reporting

📁 Project Structure

SOC-Analyst-Lab/
│
├── README.md
│
├── windows/
│   └── win-server.ps1
│
├── linux/
│   └── linux.sh
│
├── splunk/
│   ├── indexes/
│   ├── inputs/
│   └── searches/
│
├── screenshots/
│   ├── architecture.png
│   ├── splunk-dashboard.png
│   ├── windows-events.png
│   ├── sysmon-events.png
│   └── linux-events.png
│
└── docs/
    └── SOC-Lab-Manual.pdf

⚙️ Configuration Summary

┌─────────────────────────────────────────┐
│              SOC LAB                    │
├─────────────────────────────────────────┤
│ Network       192.168.10.0/24           │
│ Gateway       192.168.10.2              │
│                                         │
│ DC01-CORP     192.168.10.20             │
│ Ubuntu        192.168.10.30             │
│ Splunk Host   192.168.10.1              │
│                                         │
│ Splunk Port   TCP 9997                  │
│ Domain        corp.local                │
└─────────────────────────────────────────┘

🛠️ Technologies
Technology	Purpose
🛡️ Splunk Enterprise	SIEM & Log Analysis
🪟 Windows Server	Active Directory & DNS
🐧 Ubuntu	Linux Server
🔬 Sysmon	Windows Telemetry
📡 Universal Forwarder	Log Collection
⚡ PowerShell	Windows Automation
🔐 auditd	Linux Auditing
🌐 VMware VMnet8	Isolated Lab Network
🎯 Learning Objectives

✓ SOC Monitoring
✓ SIEM Operations
✓ Windows Event Analysis
✓ Linux Log Analysis
✓ Sysmon Investigation
✓ PowerShell Monitoring
✓ Authentication Monitoring
✓ Security Alert Triage
✓ Threat Detection
✓ Incident Investigation
✓ Security Automation

📸 Screenshots

Add your real lab screenshots here:
🛡️ Splunk Dashboard


🪟 Windows Events


🔬 Sysmon Events


🐧 Linux Events


🚀 Lab Flow

        ┌───────────────┐
        │ VMware VMnet8  │
        └───────┬───────┘
                │
       ┌────────┴─────────┐
       │                  │
       ▼                  ▼
 Windows Server         Ubuntu
 DC01-CORP           srv-linux-01
       │                  │
       │                  │
       └────────┬─────────┘
                │
                │ Telemetry
                ▼
       ┌─────────────────┐
       │     Splunk      │
       │ 192.168.10.1    │
       │     :9997       │
       └────────┬────────┘
                │
                ▼
       🔎 SOC Investigation

🏁 Result

The completed lab provides a centralized SOC monitoring environment where:

Windows + Linux → Telemetry → Splunk → Detection → Investigation

Windows Server provides Active Directory and primary DNS for the lab. Ubuntu and Windows Server remain directly connected through the VMnet8 network, while each system independently forwards its own telemetry to Splunk.
👨‍💻 SOC Analyst Lab

Built for hands-on cybersecurity learning, SOC monitoring, SIEM analysis, and blue-team practice.
