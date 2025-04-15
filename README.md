# AI-Dev-Bootstrap

## Overview
AI Dev Bootstrap is a framework for AI-assisted software development, designed to enhance collaboration between agent personas and human developers. It provides a structured approach to documentation, context management, and development workflows.

## Framework Structure
```
.
├── README.md   # Framework documentation
└── docs/
    ├── rules/      # copies of  `.cursor/rules` mdc files
    │   ├── agent-behavior-rule.mdc
    │   ├── arch-mode.mdc
    │   ├── constraints-requirements.mdc
    │   ├── dev-mode.mdc
    │   ├── mode-switch-rule.mdc
    │   ├── qa-mode.mdc
    │   └── tpm-mode.mdc
    │
    └── goals.md    # template for the agent to update vision > goals > milestones > tasks      
```

## Framework
The framework provides an easy way to help Cursor Agents develop complex software projects
- **Rules**: Rules for defining how each agent persona operates
- **mode-switch**: instructions for the Cursor Agent on how to switch personas
- **Agent Behavior**: Core agent behaviors codified as a set of rules

## Getting Started
1. Clone the repository
2. Review the framework documentation in this README.md
3. Review and customize the persona modes and the agent behavior rules
4. Create a new Project Rule (`Cursor > Settings > Cursor Settings > Rules`) to create the `.cursor/rules` folder and move all `.mdc` files into it
5. Start by sharing the vision for the project in the `goals.md` file
6. Add relevant details for your project to the `constraints-requirements.mdc` file
7. Work with the `technical product manager` agent persona to collaboratively develop the plan for implementing your vision
8. Work with the `architect` agent persona to define the technical requirements and major milestones
9. Work with the `developer` agent persona to write the code
10. Work with the `qa` agent persona to test the code
