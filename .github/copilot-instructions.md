# Copilot Instructions

## Architecture

This is an Azure Solution Accelerator for real-time manufacturing intelligence built on **Microsoft Fabric** and **Azure Event Hub**. The deployment is fully automated via Azure Developer CLI (`azd`).

**Data flow:** Telemetry Simulator → Azure Event Hub → Fabric Eventstream → Fabric Eventhouse (KQL DB) → Real-Time Dashboard + Activator (anomaly alerts) + Data Agent (conversational AI)

**Key layers:**

- `infra/main.bicep` — Provisions Azure resources (Event Hub Namespace, Fabric Capacity)
- `infra/scripts/fabric/` — Python orchestration that creates and configures all Fabric artifacts (workspace, eventhouse, eventstream, activator, dashboard, data agent). Entry point: `deploy_fabric_rti.py`
- `src/entities/` — Domain models (`Asset`, `AssetType`, `Event`) using Python dataclasses
- `src/simulator/` — Real-time event simulator that sends synthetic telemetry to Event Hub
- `src/definitions/` — JSON definitions for Fabric items (Activator rules, Real-Time Dashboard, Eventstream)
- `src/kql/` — KQL queries for data analysis and dashboard tiles
- `src/data_agent/` — Instructions and configuration for the Fabric Data Agent
- `infra/data/` — Generated CSV sample data (locations, sites, assets, products, events)

## Build & Lint

```bash
# Install dependencies
pip install -r requirements.txt

# Lint (CI uses this on src/ and infra/)
flake8 src
flake8 infra/scripts

# Lint a single file
flake8 src/simulator/event_simulator.py
```

There is no test suite in this repository.

## Deployment

```bash
# Full deploy (provisions Azure + configures Fabric)
azd up

# Tear down
azd down
```

The `azd up` command runs Bicep provisioning, then a `postprovision` hook executes `infra/scripts/fabric/deploy_fabric_rti.py` which orchestrates all Fabric setup.

## Running the Simulator

```bash
cd src
python -m simulator.event_simulator --interval 5
```

Requires `AZURE_EVENT_HUB_NAMESPACE_HOSTNAME` and `AZURE_EVENT_HUB_NAME` environment variables (automatically loaded from the azd environment via `AZDEnvironmentLoader`).

## Regenerating Sample Data

```bash
cd src
python sample_data.py
```

Outputs CSV files to `infra/data/`.

## Conventions

- **Python 3.11**, formatted with **Black** (line length 88). Flake8 config in `.flake8` mirrors this.
- Domain models use `@dataclass` with PascalCase field names matching the KQL/Event Hub schema (e.g., `AssetId`, `Temperature`, `DefectProbability`).
- Authentication always uses `AzureCliCredential` — no service principals or connection strings stored in code.
- Environment configuration flows from azd: Bicep outputs → `.azure/<env>/.env` → Python scripts read via `AZDEnvironmentLoader` or `os.getenv()`.
- Fabric deployment scripts in `infra/scripts/fabric/` each handle one Fabric artifact. They are orchestrated sequentially by `deploy_fabric_rti.py`.
- `sys.path` manipulation is used in scripts to enable sibling-directory imports (e.g., `src/simulator/` imports from `src/entities/`).
- KQL table schemas are defined in the `Event` dataclass (`get_table_schema()`) and used by the data ingestion scripts.
