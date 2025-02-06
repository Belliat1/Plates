import cv2
import numpy as np
import pytesseract
from PIL import Image
import sqlite3
import re

# Configurar Tesseract OCR
pytesseract.pytesseract.tesseract_cmd = r'C:\Program Files\Tesseract-OCR\tesseract.exe'

# Conexión a la base de datos
conexion = sqlite3.connect("vtrack360.db")
cursor = conexion.cursor()

# Crear tabla si no existe
cursor.execute("""
CREATE TABLE IF NOT EXISTS placas (
    placa TEXT PRIMARY KEY,
    propietario TEXT,
    modelo TEXT
)
""")
conexion.commit()

def verificar_placa_en_db(placa):
    conexion = sqlite3.connect("vtrack360.db")
    cursor = conexion.cursor()
    cursor.execute("SELECT * FROM placas WHERE placa = ?", (placa,))
    resultado = cursor.fetchone()
    conexion.close()
    return resultado

def limpiar_placa(placa):
    return re.sub(r'[^A-Za-z0-9]', '', placa)

# Expresión regular para validar placas colombianas
def es_placa_valida(placa):
    return re.match(r'^[A-Z]{3}\d{3,4}$', placa)

# Detectar las cámaras disponibles
def detectar_camaras():
    camaras_disponibles = []
    for i in range(10):  # Probar índices de cámaras desde 0 hasta 9
        cap = cv2.VideoCapture(i, cv2.CAP_DSHOW)
        if cap.isOpened():
            camaras_disponibles.append(i)
            cap.release()
    return camaras_disponibles

# Configuración de GPU para OpenCV (si está disponible)
if cv2.cuda.getCudaEnabledDeviceCount() > 0:
    print("GPU detectada. Configurando procesamiento con OpenCV CUDA.")
    use_gpu = True
    gpu_frame_converter = cv2.cuda.createGray()
else:
    print("No se detectó GPU compatible. Usando procesamiento con CPU.")
    use_gpu = False

camaras = detectar_camaras()
if not camaras:
    print("No se encontraron cámaras disponibles.")
    exit()

print("Cámaras disponibles:")
for idx, cam in enumerate(camaras):
    print(f"{idx}: Cámara {cam}")

indice_camara = int(input("Selecciona el índice de la cámara que deseas usar: "))
if indice_camara < 0 or indice_camara >= len(camaras):
    print("Índice de cámara no válido.")
    exit()

# Usar la cámara seleccionada
cap = cv2.VideoCapture(camaras[indice_camara])

if not cap.isOpened():
    print("No se pudo acceder a la cámara seleccionada.")
    exit()

# Configurar resolución de la cámara
cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1920)  # Ajusta según la resolución deseada
cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 1080)

while True:
    ret, frame = cap.read()

    if not ret:
        print("No se pudo leer el cuadro de la cámara.")
        break

    if use_gpu:
        # Procesamiento con GPU
        gpu_frame = cv2.cuda_GpuMat()
        gpu_frame.upload(frame)
        gray_gpu = cv2.cuda.cvtColor(gpu_frame, cv2.COLOR_BGR2GRAY)
        bin_gpu = cv2.cuda.threshold(gray_gpu, 150, 255, cv2.THRESH_BINARY)[1]
        frame = bin_gpu.download()
    else:
        # Procesamiento con CPU
        gray_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        _, frame = cv2.threshold(gray_frame, 150, 255, cv2.THRESH_BINARY)

    # Detectar contornos
    contornos, _ = cv2.findContours(frame, cv2.RETR_TREE, cv2.CHAIN_APPROX_SIMPLE)
    contornos = sorted(contornos, key=lambda x: cv2.contourArea(x), reverse=True)

    for contorno in contornos:
        area = cv2.contourArea(contorno)
        if 1000 < area < 15000:  # Ajustar área según tamaño típico de la placa
            x, y, ancho, alto = cv2.boundingRect(contorno)

            # Recortar posible placa
            placa_roi = frame[y:y+alto, x:x+ancho]

            # Convertir ROI a escala de grises y binarizar
            placa_gray = cv2.cvtColor(placa_roi, cv2.COLOR_BGR2GRAY)
            _, placa_bin = cv2.threshold(placa_gray, 150, 255, cv2.THRESH_BINARY)

            # Convertir a imagen PIL para Tesseract
            placa_pil = Image.fromarray(placa_bin)
            texto = pytesseract.image_to_string(placa_pil, config='--psm 8').strip()
            texto_limpio = limpiar_placa(texto)

            if es_placa_valida(texto_limpio):
                print(f"Placa detectada: {texto_limpio}")
                resultado = verificar_placa_en_db(texto_limpio)

                color = (0, 255, 0) if resultado else (0, 0, 255)
                cv2.rectangle(frame, (x, y), (x+ancho, y+alto), color, 2)
                cv2.putText(frame, texto_limpio, (x, y-10), cv2.FONT_HERSHEY_SIMPLEX, 0.8, color, 2)

    # Mostrar el cuadro procesado
    frame_resized = cv2.resize(frame, (1280, 720))  # Ajustar resolución para mostrar
    cv2.imshow("Detección de Placas", frame_resized)

    if cv2.waitKey(10) == 27:  # Presionar ESC para salir
        break

cap.release()
cv2.destroyAllWindows()
conexion.close()
