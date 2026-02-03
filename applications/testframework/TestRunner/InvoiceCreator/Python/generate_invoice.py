import pdfkit
from jinja2 import Template
import os
from pdfkit.configuration import Configuration
import base64
import uuid
from datetime import datetime

def render_pdf(template, context: dict, binary_path: str):

    items = context.get('items', [])
     # Calculate derived parameters
    for item in items:
        unitPrice = float(item.get('unit_price', 0))
        quantity = float(item.get('quantity', 0))
        discount = float(item.get('discount', 0))
        tax_rate = float(item.get('tax_rate', 0))
        item['net_amount'] = unitPrice * quantity - discount
        if tax_rate == 0:
            item['tax_amount'] = 0
        else:
            item['tax_amount'] = round(item['net_amount'] * (tax_rate / 100), 2)  # Assuming tax_rate is a percentage
        item['total_amount'] = round(item['net_amount'] + item['tax_amount'], 2)
    
    context['total_amount'] = sum(item['total_amount'] for item in items)

    if context['invoice_date'] == 'today':
        context['invoice_date'] = datetime.now().strftime("%Y-%m-%d")

    # Render the template with data
    template = Template(template)
    html_out = template.render(context)

    # Configure wkhtmltopdf path
    print(f"wkhtmltopdf_path: {binary_path}")
    config = None
    if os.path.exists(binary_path):
        config = Configuration(wkhtmltopdf=binary_path)
    
    random_pdfname = str(uuid.uuid4())
    output_pdf_path = f"{random_pdfname}.pdf"

    # Generate PDF
    pdfkit.from_string(html_out, output_pdf_path, options={
        'enable-local-file-access': None
    }, configuration=config)
    
    base64_encoded_data = None
    with open(output_pdf_path, 'rb') as binary_file:
        binary_file_data = binary_file.read()
        base64_encoded_data = base64.b64encode(binary_file_data)

        # Clean up the generated PDF file
    os.remove(output_pdf_path)
    return base64_encoded_data.decode('utf-8')