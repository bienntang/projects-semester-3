import smtplib

def send():
    try:
        x = smtplib.SMTP('smtp.gmail.com', 587)
        x.starttls()
        x.login("karimyqueen@gmail.com", "vpiptiqrabukcqur")
        subject = "PROMO BAKMIE SAUDAGAR"
        body_text = "Terdapat Promo Potongan 20% Bakmie Saudagar\nJangan lupa berikan gaya terbaikmu"
        message = "Subject: {}\n\n{}".format(subject, body_text)
        x.sendmail("karimyqueen@gmail.com", "beenwid14@gmail.com", message)
        x.sendmail("karimyqueen@gmail.com", "dhanatasya3@gmail.com", message)
        print("Success")
    except Exception as exception:
        print(exception)
        print("Failure")

if __name__ == "__main__":
    send()
