import smtplib

def send():
    try:
        x = smtplib.SMTP('smtp.gmail.com', 587)
        x.starttls()
        x.login("emailsender", "appspassword")
        subject = "PROMO BAKMIE SAUDAGAR"
        body_text = "Terdapat Promo Potongan 20% Bakmie Saudagar\nJangan lupa berikan gaya terbaikmu"
        message = "Subject: {}\n\n{}".format(subject, body_text)
        x.sendmail("emailsender", "emailreceiver", message)
        x.sendmail("emailsender", "emailreceiver", message)
        print("Success")
    except Exception as exception:
        print(exception)
        print("Failure")

if __name__ == "__main__":
    send()
