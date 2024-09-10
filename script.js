// Globe visualization
let globeScene, globeCamera, globeRenderer, globe, countryLabels = [];

function initGlobe() {
    globeScene = new THREE.Scene();
    globeCamera = new THREE.PerspectiveCamera(75, 680 / 420, 0.1, 1000);
    globeRenderer = new THREE.WebGLRenderer();
    globeRenderer.setSize(680, 420);
    document.getElementById('globeContainer').appendChild(globeRenderer.domElement);

    const geometry = new THREE.SphereGeometry(5, 32, 32);
    const material = new THREE.MeshBasicMaterial({ color: 0x9d4edd, wireframe: true });
    globe = new THREE.Mesh(geometry, material);
    globeScene.add(globe);

    // Country labels
    const countries = [
        { name: 'Netherlands', position: { x: 1.5, y: 2, z: 4 } },
        { name: 'Switzerland', position: { x: 2, y: 0, z: 4.5 } },
        { name: 'Japan', position: { x: -3, y: 1.5, z: 4 } },
        { name: 'United States', position: { x: -2.5, y: -1, z: 4 } }
    ];

    countries.forEach(country => {
        const div = document.createElement('div');
        div.className = 'countryLabel';
        div.textContent = country.name;
        document.body.appendChild(div);
        countryLabels.push({ element: div, position: country.position });
    });

    globeCamera.position.z = 15;

    animateGlobe();
}

function animateGlobe() {
    requestAnimationFrame(animateGlobe);
    globe.rotation.y += 0.005;

    // Update country label positions
    countryLabels.forEach(label => {
        const vector = new THREE.Vector3(label.position.x, label.position.y, label.position.z);
        vector.project(globeCamera);
        const x = (vector.x * 0.5 + 0.5) * globeRenderer.domElement.clientWidth;
        const y = (vector.y * -0.5 + 0.5) * globeRenderer.domElement.clientHeight;
        label.element.style.transform = `translate(-50%, -50%) translate(${x}px, ${y}px)`;
    });

    globeRenderer.render(globeScene, globeCamera);
}

// Mesh network visualization
let meshScene, meshCamera, meshRenderer, meshNodes = [], connections = [];

function initMesh() {
    meshScene = new THREE.Scene();
    meshCamera = new THREE.PerspectiveCamera(75, 680 / 420, 0.1, 1000);
    meshRenderer = new THREE.WebGLRenderer();
    meshRenderer.setSize(680, 420);
    document.getElementById('meshContainer').appendChild(meshRenderer.domElement);

    const nodeMaterial = new THREE.MeshBasicMaterial({ color: 0x9d4edd });

    for (let i = 0; i < 20; i++) {
        const geometry = new THREE.SphereGeometry(0.1, 32, 32);
        const node = new THREE.Mesh(geometry, nodeMaterial);
        node.position.set(
            Math.random() * 10 - 5,
            Math.random() * 10 - 5,
            Math.random() * 10 - 5
        );
        meshNodes.push(node);
        meshScene.add(node);
    }

    // Add animated connections (lines) between nodes
    const lineMaterial = new THREE.LineBasicMaterial({ color: 0x9d4edd });
    meshNodes.forEach((node1, index) => {
        meshNodes.slice(index + 1).forEach(node2 => {
            const geometry = new THREE.BufferGeometry().setFromPoints([node1.position, node2.position]);
            const line = new THREE.Line(geometry, lineMaterial);
            line.userData.pulseSpeed = Math.random() * 0.01 + 0.01;
            line.userData.offset = Math.random();
            connections.push(line);
            meshScene.add(line);
        });
    });

    meshCamera.position.z = 15;

    animateMesh();
}

function animateMesh() {
    requestAnimationFrame(animateMesh);
    meshNodes.forEach(node => {
        node.position.x += (Math.random() - 0.5) * 0.01;
        node.position.y += (Math.random() - 0.5) * 0.01;
        node.position.z += (Math.random() - 0.5) * 0.01;
    });

    // Update connection lines with a pulsing effect
    connections.forEach(line => {
        const scale = Math.sin(Date.now() * line.userData.pulseSpeed + line.userData.offset * Math.PI * 2) * 0.1 + 1;
        line.scale.set(scale, scale, scale);
        line.geometry.attributes.position.needsUpdate = true;
    });

    meshRenderer.render(meshScene, meshCamera);
}

// Network traffic chart
let trafficChart;

function initTrafficChart() {
    const ctx = document.getElementById('trafficChart').getContext('2d');
    trafficChart = new Chart(ctx, {
        type: 'line',
        data: {
            labels: [],
            datasets: [{
                label: 'Download',
                data: [],
                borderColor: '#9d4edd',
                tension: 0.1
            }, {
                label: 'Upload',
                data: [],
                borderColor: '#4caf50',
                tension: 0.1
            }]
        },
        options: {
            responsive: true,
            scales: {
                y: {
                    beginAtZero: true
                }
            }
        }
    });
}

function updateTrafficChart() {
    const time = new Date().toLocaleTimeString();
    trafficChart.data.labels.push(time);
    trafficChart.data.datasets[0].data.push(Math.random() * 10);
    trafficChart.data.datasets[1].data.push(Math.random() * 5);

    if (trafficChart.data.labels.length > 10) {
        trafficChart.data.labels.shift();
        trafficChart.data.datasets[0].data.shift();
        trafficChart.data.datasets[1].data.shift();
    }

    trafficChart.update();
}

// Initialize everything
document.addEventListener('DOMContentLoaded', () => {
    initGlobe();
    initMesh();
    initTrafficChart();
    setInterval(updateTrafficChart, 2000);

    // Simulated device list
    const devices = ['Laptop', 'Smartphone', 'Tablet'];
    const deviceList = document.getElementById('deviceList');
    devices.forEach(device => {
        const li = document.createElement('li');
        li.textContent = `${device} `;
        const status = document.createElement('span');
        status.className = `status ${Math.random() > 0.5 ? 'active' : 'inactive'}`;
        status.textContent = status.classList.contains('active') ? 'Active' : 'Inactive';
        li.appendChild(status);
        deviceList.appendChild(li);
    });

    // Simulated connection status
    document.getElementById('connectionStatus').textContent = 'Connected';
    document.getElementById('connectionStatus').className = 'status active';
    document.getElementById('protocol').textContent = 'OpenVPN';
    document.getElementById('serverLocation').textContent = 'Netherlands';

    // Country selection
    const countries = ['Netherlands', 'Switzerland', 'Japan', 'United States'];
    const countrySelect = document.getElementById('countrySelect');
    countries.forEach(country => {
        const option = document.createElement('option');
        option.textContent = country;
        countrySelect.appendChild(option);
    });

    // Button event listeners
    document.getElementById('connectVPN').addEventListener('click', () => {
        alert('Connecting to VPN...');
    });

    document.getElementById('connectTor').addEventListener('click', () => {
        alert('Connecting to Tor network...');
    });

    // Simulated logs
    const logContainer = document.getElementById('logContainer');
    setInterval(() => {
        const log = document.createElement('p');
        log.textContent = `${new Date().toLocaleString()} - ${Math.random() > 0.5 ? 'VPN' : 'Tor'} connection ${Math.random() > 0.5 ? 'established' : 'changed'}`;
        logContainer.prepend(log);
        if (logContainer.children.length > 5) {
            logContainer.removeChild(logContainer.lastChild);
        }
    }, 5000);
});
