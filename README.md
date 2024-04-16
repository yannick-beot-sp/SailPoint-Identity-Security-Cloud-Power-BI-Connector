# SailPoint Identity Security Cloud - Power BI Connector

This project allows Power BI to query data from Identity Security Cloud (API)[https://developer.sailpoint.com/]. 

## Installation

1. Create a `[Documents]\Power BI Desktop\Custom Connectors` directory.
2. Ensure Power BI Desktop is closed.
3. Download [SailPoint Identity Security Cloud Power BI Connector.mez](XXX) and place it in that directory.
4. Open Power BI Desktop and enable loading unsigned connectors (*File > Options and settings > Options > Security > Data Extensions > Allow any extension to load without warning or validation*)
5. If you have changed this parameter, restart Power BI Desktop

Read the [PBI documentation](https://learn.microsoft.com/power-bi/connect-data/desktop-connector-extensibility#data-extension-security) if you have any trouble.

## Usage

An example is provided in the session ["BYOB - bring your own BI" from the SailPoint Developer Days 2024](https://www.youtube.com/watch?v=8X8Mjbgvocg).

### Requirements
To use this connector, you need:
1. The base URL of the API (e.g. `https://mycompany.api.identitynow.com`)
2. A Personal Access Token (PAT)

### Sample report

A sample report is provided in the folder `Power BI Templates` of this repository.

## Development

### Build

1. Install Visual Studio Code.
2. Install the VS Code extensions [Power Query / M Language](https://marketplace.visualstudio.com/items?itemName=PowerQuery.vscode-powerquery) and [Power Query SDK](https://marketplace.visualstudio.com/items?itemName=PowerQuery.vscode-powerquery-sdk).
3. Clone this repository and open it in VS Code
4. Compile and install (*Command Palette > Run Task > Build and copy to Customs Connectors folder* or press <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>B</kbd>)


### Test

1. Update the `ISC.query.pq` to pass the API base URL for your environment.
2. Set the PAT to be used for testing by using the command "Power query: Set credential".
3. You can also change the content to get the data you want from the queries.
4. Evaluate the `ISC.query.pq` by pressing <kbd>F5</kbd>