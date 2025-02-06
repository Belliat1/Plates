import streamlit as st
import cv2
import numpy as np
import easyocr
import imutils
from PIL import Image

# 📷 Obtener la lista de cámaras disponibles
def listar_camaras():
    index = 0
    available_cameras = []
    while True:
        cap = cv2.VideoCapture(index)
        if not cap.read()[0]:
            break
        else:
            available_cameras.append(index)
        cap.release()
        index += 1
    return available_cameras

# 📷 Inicializar la cámara seleccionada
def iniciar_camara(camara_index):
    cap = cv2.VideoCapture(camara_index)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)  
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    return cap

# 📌 Función para detectar y extraer la placa
def detectar_placa(frame):
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    bfilter = cv2.bilateralFilter(gray, 11, 17, 17)  # Reducción de ruido
    edged = cv2.Canny(bfilter, 30, 200)  # Detección de bordes
    
    keypoints = cv2.findContours(edged.copy(), cv2.RETR_TREE, cv2.CHAIN_APPROX_SIMPLE)
    contours = imutils.grab_contours(keypoints)
    contours = sorted(contours, key=cv2.contourArea, reverse=True)[:10]
    
    location = None
    for contour in contours:
        approx = cv2.approxPolyDP(contour, 10, True)
        if len(approx) == 4:
            location = approx
            break

    placa_texto = None
    if location is not None:
        mask = np.zeros(gray.shape, np.uint8)
        new_image = cv2.drawContours(mask, [location], 0, 255, -1)
        new_image = cv2.bitwise_and(frame, frame, mask=mask)
        (x, y) = np.where(mask == 255)
        (x1, y1) = (np.min(x), np.min(y))
        (x2, y2) = (np.max(x), np.max(y))
        cropped_image = gray[x1:x2 + 1, y1:y2 + 1]
        
        reader = easyocr.Reader(['es'])
        result = reader.readtext(cropped_image)
        
        if result:
            placa_texto = result[0][-2]
    
    return placa_texto, frame

# 📌 Configuración de Streamlit
st.set_page_config(page_title="Detección de Placas en Vivo", layout="wide")

# 📌 Encabezado
st.header("📷 Detección de Placas en Vivo")

# 📷 Selección de Cámara
camaras_disponibles = listar_camaras()
camara_seleccionada = st.selectbox("Selecciona una Cámara", camaras_disponibles)

# 📷 Botón para activar la cámara
if st.button("Iniciar Cámara"):
    cap = iniciar_camara(camara_seleccionada)

    # 📷 Mostrar video en vivo
    stframe = st.empty()
    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            st.error("❌ No se pudo acceder a la cámara.")
            break

        # 📌 Detectar la placa
        placa, frame = detectar_placa(frame)
        
        # 📌 Mostrar resultado en Streamlit
        frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        stframe.image(frame_rgb, channels="RGB", use_column_width=True)

        # 📌 Mostrar la placa detectada
        if placa:
            st.success(f"🚗 Placa Detectada: {placa}")
        else:
            st.warning("⏳ Buscando placa...")

        # Salir del bucle si el usuario presiona "Stop"
        if st.button("Detener Cámara"):
            break

    cap.release()
    cv2.destroyAllWindows()
