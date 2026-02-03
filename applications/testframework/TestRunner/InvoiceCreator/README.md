The InvoiceCreator server/API in this folder is needed to run accuracy tests for the Payables Agent.

To run:

- Create a virtual Python environment and install `pdfkit` and `Flask`:
```powershell
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install pdfkit
pip install flask
```
- install `wkhtmltopdf`, e.g.,
```
choco install wkhtmltopdf -y
```
- run the server
```powershell
.\RunServer.ps1
```